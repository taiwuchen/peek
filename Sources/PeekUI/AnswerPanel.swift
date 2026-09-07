import AppKit
import PeekCore
import SwiftUI

@MainActor
final class AnswerPanel: NSPanel {
    private var anchor: CGRect?
    private var mouseLocation = CGPoint.zero
    private var globalMouseMonitor: Any?
    private var localMonitor: Any?
    private var onDismiss: (() -> Void)?

    init(session: AskSession, openSettings: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
                   styleMask: [.nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        self.onDismiss = onDismiss
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        let host = NSHostingView(rootView: AnswerContent(session: session, openSettings: openSettings,
                                                        close: { [weak self] in self?.dismiss() },
                                                        resize: { [weak self] in self?.resize(height: $0) }))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        contentView = effect
        setAccessibilityLabel("Peek answer")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present(anchor: CGRect?) {
        self.anchor = anchor
        mouseLocation = NSEvent.mouseLocation
        position()
        orderFrontRegardless()
        installMonitors()
    }

    func dismiss() {
        orderOut(nil)
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMouseMonitor = nil
        localMonitor = nil
        onDismiss?()
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    private func resize(height: CGFloat) {
        let screenHeight = screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        let size = CGSize(width: min(420, screen?.visibleFrame.width ?? 420),
                          height: min(max(160, height), screenHeight - 24))
        guard abs(frame.height - size.height) > 1 || frame.width != size.width else { return }
        setContentSize(size)
        if isVisible { position() }
    }

    private func position() {
        setFrameOrigin(panelOrigin(anchor: anchor, panelSize: frame.size,
                                   visibleFrames: NSScreen.screens.map(\.visibleFrame),
                                   primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0,
                                   mouseLocation: mouseLocation))
    }

    private func installMonitors() {
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.keyCode == 53 { self.dismiss(); return true }
                return false
            }
            return consumed ? nil : event
        }
    }
}

private struct AnswerContent: View {
    @Bindable var session: AskSession
    let openSettings: () -> Void
    let close: () -> Void
    let resize: (CGFloat) -> Void
    @State private var answerHeight: CGFloat = 0
    @State private var shellHeight: CGFloat = 0
    @FocusState private var questionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    preview
                    Spacer(minLength: 8)
                    Button(action: close) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help("Close (Esc)")
                        .accessibilityLabel("Close answer")
                }
                if session.capture != nil {
                    HStack {
                        TextField("Ask about this", text: $session.question)
                            .textFieldStyle(.roundedBorder)
                            .focused($questionFocused)
                            .onSubmit { session.send() }
                        Button(action: session.send) { Image(systemName: "arrow.up.circle.fill") }
                            .buttonStyle(.plain).font(.title2)
                            .disabled(session.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.model.isEmpty)
                            .accessibilityLabel("Send question")
                    }
                }
                if let message = session.message {
                    Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if let permission = session.permission {
                        HStack {
                            Button("Request access") {
                                switch permission {
                                case .accessibility: Permissions.requestAccessibility()
                                case .screenRecording: Permissions.requestScreenRecording()
                                }
                            }
                            Button("System Settings") { openPrivacySettings(permission) }
                        }
                    } else if session.capture != nil {
                        Button("Open Settings", action: openSettings)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shellHeight = $0; updateHeight() }
            if !session.answer.isEmpty {
                ScrollView {
                    MarkdownAnswer(text: session.answer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { answerHeight = $0; updateHeight() }
                }
                .frame(maxHeight: min(answerHeight, 370))
                .layoutPriority(-1)
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(session.providers, id: \.id) { provider in
                        Button(provider.displayName) { session.selectProvider(provider.id) }
                    }
                } label: {
                    Text(session.providers.first(where: { $0.id == session.providerID })?.displayName ?? "Choose provider")
                }
                .menuStyle(.borderlessButton).fixedSize()
                Text(session.model).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if session.isStreaming { ProgressView().controlSize(.mini) }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.answer, forType: .string)
                }
                .disabled(session.answer.isEmpty)
            }
            .font(.caption)
        }
        .padding(16)
        .onAppear { questionFocused = true; updateHeight() }
        .onChange(of: session.answer.isEmpty) { _, empty in if empty { answerHeight = 0; updateHeight() } }
    }

    @ViewBuilder private var preview: some View {
        switch session.capture?.content {
        case .text(let text): Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        case .image(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 100, maxHeight: 54)
                    .accessibilityLabel("Captured screen region")
            } else { Label("Screen region", systemImage: "viewfinder") }
        case nil: Label("Peek", systemImage: "sparkle")
        }
    }

    private func updateHeight() {
        resize(shellHeight + (session.answer.isEmpty ? 0 : min(answerHeight, 370) + 12) + 68)
    }
}
