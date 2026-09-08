import AppKit
import PeekCore
import SwiftUI

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
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(session.messages) { message in
                            ConversationTurn(message: message, note: session.responseNotes[message.id])
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
}

private struct ConversationTurn: View {
    let message: AIMessage
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
                if case .image(let data) = capture.content, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 120, alignment: isUser ? .trailing : .leading)
                        .accessibilityLabel("Captured screen region")
                } else {
                    Label("Screen region", systemImage: "viewfinder")
                }
            }
            if isUser {
                if message.captures.isEmpty {
                    Text(message.text).multilineTextAlignment(.trailing).textSelection(.enabled)
                }
            } else {
                MarkdownAnswer(text: message.text)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
