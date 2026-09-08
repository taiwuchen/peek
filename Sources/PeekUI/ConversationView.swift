import AppKit
import PeekCore
import SwiftUI
import UniformTypeIdentifiers

struct ConversationView: View {
    @Bindable var session: AskSession
    let openSettings: () -> Void
    let close: () -> Void
    @State private var followsResponse = true
    @State private var isUserScrolling = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    ForEach(session.modes) { mode in
                        Button(mode.name) { session.selectMode(mode.id) }
                    }
                } label: {
                    Text(session.modes.first(where: { $0.id == session.selectedModeID })?.name ?? "Choose mode")
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 180, alignment: .leading)
                .accessibilityLabel("Mode")
                .disabled(session.isBusy)
                PanelDragHandle().frame(maxWidth: .infinity).frame(height: 24).help("Drag to move")
                Button(action: close) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain)
                    .help("Close conversation")
                    .accessibilityLabel("Close conversation")
            }
            .padding(12)
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(session.messages) { message in
                            ConversationTurn(message: message, note: session.responseNotes[message.id])
                        }
                        if session.isStreaming {
                            ProgressView("Responding…").controlSize(.small)
                        } else if session.isCapturing {
                            Text("Select a screen region…").foregroundStyle(.secondary)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
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
            Divider()
            VStack(alignment: .leading, spacing: 10) {
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
                HStack(alignment: .bottom) {
                    Menu {
                        Button("Capture screen region", systemImage: "viewfinder", action: session.beginCapture)
                            .disabled(session.isBusy)
                        Button("Choose images…", systemImage: "photo", action: chooseImages)
                            .disabled(session.isBusy)
                        Divider()
                        Button("Settings…", systemImage: "gearshape", action: openSettings)
                    } label: {
                        Image(systemName: "paperclip")
                            .frame(width: 24, height: 30)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Attach a screenshot")
                    .accessibilityLabel("Attach a screenshot")
                    ChatComposer(text: $session.question, onSubmit: { session.send() },
                                 onImages: { session.addScreenshots($0) },
                                 onError: { session.reportInputError($0) })
                        .frame(maxWidth: .infinity)
                    if session.isBusy {
                        Button(action: session.stop) {
                            Image(systemName: "stop.circle.fill").font(.title2).frame(width: 28, height: 32)
                        }
                            .help("Stop response")
                            .accessibilityLabel("Stop response")
                    } else {
                        Button(action: session.send) {
                            Image(systemName: "arrow.up.circle.fill").font(.title2).frame(width: 28, height: 32)
                        }
                            .disabled(!session.canSend)
                            .help("Send message")
                            .accessibilityLabel("Send message")
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
    }

    private func chooseImages() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.image]
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.prompt = "Add"
        picker.begin { result in
            guard result == .OK else { return }
            do { session.addScreenshots(try ScreenshotInput.pngImages(from: picker.urls)) }
            catch { session.reportInputError(error.localizedDescription) }
        }
    }
}

private struct ConversationTurn: View {
    let message: AIMessage
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.role == .user ? "You" : "Peek").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if message.role == .assistant && !message.text.isEmpty {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    }
                    .font(.caption).buttonStyle(.borderless)
                    .accessibilityLabel("Copy answer")
                }
            }
            ForEach(Array(message.captures.enumerated()), id: \.offset) { _, capture in
                if case .image(let data) = capture.content, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 120, alignment: .leading)
                        .accessibilityLabel("Captured screen region")
                } else {
                    Label("Screen region", systemImage: "viewfinder")
                }
            }
            if message.role == .assistant {
                MarkdownAnswer(text: message.text)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            } else if message.captures.isEmpty {
                Text(message.text).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
