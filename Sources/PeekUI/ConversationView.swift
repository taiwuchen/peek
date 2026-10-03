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
            header
            Divider()
            if !isCompact {
                transcript.transition(.opacity)
                Divider()
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
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 180, alignment: .leading)
            .accessibilityLabel("Mode")
            Spacer()
            Button(action: close) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                .buttonStyle(.plain)
                .help("Close conversation")
                .accessibilityLabel("Close conversation")
        }
        .padding(12)
        // The whole header drags the window; the menu and button sit on top and keep their clicks.
        .background(PanelDragHandle())
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
    }

    private var composer: some View {
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
            if !session.draft.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(session.draft.enumerated()), id: \.offset) { index, capture in
                            AttachmentPreview(content: capture.content, maxWidth: 120, maxHeight: 56)
                                .padding(6)
                                .overlay(alignment: .topTrailing) {
                                    Button { session.removeDraftAttachment(at: index) } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove attachment")
                                    .accessibilityLabel("Remove attachment")
                                }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                // Sent attachments reappear in the transcript, so a fade here would show them twice.
                .transition(.identity)
            }
            HStack(alignment: .bottom) {
                ChatComposer(text: $session.question,
                             placeholder: placeholder,
                             onSubmit: { session.send() },
                             onAttachments: { session.addAttachments($0) },
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

    private var placeholder: String {
        if !session.draft.isEmpty { return "Add context, then press Enter" }
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
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            HStack {
                Text(isUser ? "You" : "Peek").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if !isUser {
                    Spacer()
                    if !message.text.isEmpty {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        }
                        .font(.caption).buttonStyle(.borderless)
                        .accessibilityLabel("Copy answer")
                    }
                }
            }
            ForEach(Array(message.captures.enumerated()), id: \.offset) { _, capture in
                AttachmentPreview(content: capture.content, maxWidth: 200, maxHeight: 120)
                    .frame(maxWidth: 200, alignment: isUser ? .trailing : .leading)
            }
            if isUser {
                if let text = message.captures.isEmpty ? message.text : addedContext {
                    Text(text).multilineTextAlignment(.trailing).textSelection(.enabled)
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

    var body: some View {
        switch content {
        case .image(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
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
