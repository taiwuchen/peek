import AppKit
import PeekCore
import SwiftUI

struct ConversationView: View {
    @Bindable var session: AskSession
    let openSettings: () -> Void
    let close: () -> Void
    /// Reports the compact content height so the panel can fit it.
    let fitCompact: (CGFloat) -> Void
    /// Grows the panel once the first message is sent.
    let expand: () -> Void
    @State private var followsResponse = true
    @State private var isUserScrolling = false

    /// Until the first message is sent, the panel shows only the header and composer.
    private var isCompact: Bool { session.messages.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if !isCompact {
                header
                transcript.transition(.opacity)
            }
            composer
        }
        .fixedSize(horizontal: false, vertical: isCompact)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if isCompact { fitCompact(height) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: AnswerPanel.expandDuration), value: isCompact)
        .onChange(of: isCompact) { _, compact in
            if !compact { expand() }
        }
    }

    private var header: some View {
        HStack {
            modeMenu
            Spacer()
            closeButton
        }
        .padding(10)
        // The whole header drags the window; the menu and button sit on top and keep their clicks.
        .background(PanelDragHandle())
    }

    private var modeMenu: some View {
        Menu {
            ForEach(session.modes) { mode in
                Button(mode.name) { session.selectMode(mode.id) }
                    .disabled(session.isBusy)
            }
            Divider()
            Button("Settings…", systemImage: "gearshape", action: openSettings)
        } label: {
            Text(session.modes.first(where: { $0.id == session.selectedModeID })?.name ?? "Choose mode")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(height: 30)
        .glassPill(Capsule())
        .accessibilityLabel("Mode")
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                .frame(width: 30, height: 30)
                .glassPill(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close conversation")
        .accessibilityLabel("Close conversation")
    }

    private var transcript: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(session.messages) { message in
                        ConversationTurn(message: message, addedContext: session.addedContext[message.id],
                                         note: session.responseNotes[message.id])
                    }
                    if session.isStreaming {
                        ProgressView("Responding…").controlSize(.small)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onScrollPhaseChange { _, phase, context in
                isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                if isUserScrolling || phase == .idle {
                    followsResponse = context.geometry.visibleRect.maxY >= context.geometry.contentSize.height - 24
                }
            }
            .onScrollGeometryChange(for: Bool.self) {
                $0.visibleRect.maxY >= $0.contentSize.height - 24
            } action: { _, atBottom in
                if isUserScrolling { followsResponse = atBottom }
            }
            .onChange(of: session.messages.last(where: { $0.role == .user })?.id) { _, _ in
                followsResponse = true
                scroll.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: session.messages.last?.text) { _, _ in
                if followsResponse { scroll.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    /// Compact, this is the whole panel: one row with the mode, draft, input, and close. Expanded, a floating capsule.
    /// The input keeps its place in both, so it keeps focus as the panel grows.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = session.message {
                Text(message).font(.callout).textSelection(.enabled)
                HStack {
                    if session.needsScreenRecordingPermission {
                        Button("Request access") { Permissions.requestScreenRecording() }
                        Button("System Settings") { openPrivacySettings() }
                    }
                    if session.canRetry { Button("Retry", action: session.retry) }
                    Button("Settings", action: openSettings)
                }
            }
            // One screenshot fits inline in the compact bar; more get their own row so the input keeps its width.
            if !session.draft.isEmpty && !(isCompact && session.draft.count == 1) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { drafts(maxWidth: 120, maxHeight: 56) }
                        .padding(6)
                }
                .scrollIndicators(.hidden)
                // Sent attachments reappear in the transcript, so a fade here would show them twice.
                .transition(.identity)
            }
            HStack(alignment: isCompact ? .center : .bottom, spacing: 8) {
                if isCompact {
                    modeMenu
                    if session.draft.count == 1 { drafts(maxWidth: 60, maxHeight: 30) }
                }
                ChatComposer(text: $session.question,
                             placeholder: placeholder,
                             onSubmit: { session.send() },
                             onAttachments: { session.addAttachments($0) },
                             onError: { session.reportInputError($0) })
                    .frame(maxWidth: .infinity)
                if !isCompact { attachButton }
                sendButton
                if isCompact { closeButton }
            }
            .padding(.leading, isCompact ? 0 : 14)
            .padding(.trailing, isCompact ? 0 : 6)
            .padding(.vertical, isCompact ? 0 : 4)
            .glassPill(RoundedRectangle(cornerRadius: 22, style: .continuous), visible: !isCompact)
        }
        .padding(10)
        // Compact has no header, so the bar itself drags the window.
        .background { if isCompact { PanelDragHandle() } }
    }

    private func drafts(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        ForEach(Array(session.draft.enumerated()), id: \.offset) { index, capture in
            AttachmentPreview(content: capture.content, maxWidth: maxWidth, maxHeight: maxHeight, cornerRadius: 8)
                .overlay(alignment: .topTrailing) {
                    Button { session.removeDraftAttachment(at: index) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .help("Remove attachment")
                    .accessibilityLabel("Remove attachment")
                }
        }
    }

    private var attachButton: some View {
        Button(action: chooseAttachments) {
            Image(systemName: "paperclip").font(.system(size: 14)).foregroundStyle(.secondary)
                .frame(width: 26, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.isBusy)
        .help("Attach images, PDFs, or text files")
        .accessibilityLabel("Attach files")
    }

    private func chooseAttachments() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.image, .pdf, .text]
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        // Above the floating conversation panel, which would otherwise cover it.
        picker.level = .modalPanel
        NSApp.activate()
        Task {
            guard await picker.begin() == .OK else { return }
            do {
                session.addAttachments(try AttachmentInput.attachments(from: picker.urls))
            } catch {
                session.reportInputError(error.localizedDescription)
            }
        }
    }

    @ViewBuilder private var sendButton: some View {
        if session.isBusy {
            Button(action: session.stop) {
                Image(systemName: "stop.circle.fill").font(.system(size: 26)).frame(width: 30, height: 34)
            }
            .buttonStyle(.plain)
            .help("Stop response")
            .accessibilityLabel("Stop response")
        } else {
            Button(action: session.send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 26)).frame(width: 30, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(!session.canSend)
            .help("Send message")
            .accessibilityLabel("Send message")
        }
    }

    private var placeholder: String {
        if !session.draft.isEmpty { return isCompact ? "Add context…" : "Add context, then press Enter" }
        return isCompact ? "Ask a question" : "Ask a follow-up"
    }
}

private struct ConversationTurn: View {
    let message: AIMessage
    let addedContext: String?
    let note: String?

    private var isUser: Bool { message.role == .user }

    var body: some View {
        if isUser {
            turn.containerRelativeFrame(.horizontal, alignment: .trailing) { length, _ in length * 0.85 }
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            turn.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var turn: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            ForEach(Array(message.captures.enumerated()), id: \.offset) { _, capture in
                AttachmentPreview(content: capture.content, maxWidth: 200, maxHeight: 120, cornerRadius: 14)
                    .frame(maxWidth: 200, alignment: isUser ? .trailing : .leading)
            }
            if isUser {
                if let text = message.captures.isEmpty ? message.text : addedContext {
                    Text(text).multilineTextAlignment(.trailing).textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassPill(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            } else {
                MarkdownAnswer(text: message.text)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/// A screenshot thumbnail, or a labelled icon for an attached file.
private struct AttachmentPreview: View {
    let content: Capture.Content
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    var cornerRadius: CGFloat = 0

    var body: some View {
        switch content {
        case .image(let data):
            if let image = NSImage(data: data) {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.separator))
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .accessibilityLabel("Screenshot")
            } else {
                Label("Screen region", systemImage: "viewfinder")
            }
        case .pdf(let name, _):
            Label(name, systemImage: "doc.richtext").lineLimit(1).frame(maxWidth: maxWidth)
        case .text(let name, _):
            Label(name, systemImage: "doc.text").lineLimit(1).frame(maxWidth: maxWidth)
        }
    }
}

/// A translucent fill with a light rim, for controls floating on the panel's glass.
private struct GlassPill<S: InsettableShape>: ViewModifier {
    let shape: S
    let visible: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        content
            .background(.white.opacity(visible ? (dark ? 0.1 : 0.5) : 0), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(visible ? (dark ? 0.22 : 0.8) : 0)).allowsHitTesting(false))
    }
}

extension View {
    fileprivate func glassPill<S: InsettableShape>(_ shape: S, visible: Bool = true) -> some View {
        modifier(GlassPill(shape: shape, visible: visible))
    }
}
