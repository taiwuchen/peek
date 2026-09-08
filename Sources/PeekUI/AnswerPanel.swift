import AppKit
import PeekCore
import SwiftUI

@MainActor
final class AnswerPanel: NSPanel, NSWindowDelegate {
    private let session: AskSession
    private var hasPosition = false

    init(session: AskSession, openSettings: @escaping () -> Void) {
        self.session = session
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
                   styleMask: [.resizable, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        title = "Peek"
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        minSize = NSSize(width: 360, height: 320)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        let host = NSHostingView(rootView: ConversationView(session: session, openSettings: openSettings,
                                                           close: { [weak self] in self?.close() }))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        contentView = effect
        delegate = self
        setAccessibilityLabel("Peek conversation")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present(anchor: CGRect?) {
        if !hasPosition {
            setFrameOrigin(panelOrigin(anchor: anchor, panelSize: frame.size,
                                       visibleFrames: NSScreen.screens.map(\.visibleFrame),
                                       primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0,
                                       mouseLocation: NSEvent.mouseLocation))
            hasPosition = true
        }
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        session.close()
        hasPosition = false
        super.close()
    }

    override func cancelOperation(_ sender: Any?) {}

    func windowDidBecomeKey(_ notification: Notification) {
        session.refreshSettings()
    }
}

struct PanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}
