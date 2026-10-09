import AppKit
import PeekCore
import SwiftUI

@MainActor
final class AnswerPanel: NSPanel, NSWindowDelegate {
    let session: AskSession
    var onClose: (() -> Void)?
    static let expandDuration: TimeInterval = 0.3
    private static let fullSize = NSSize(width: 420, height: 500)
    private static let fullMinSize = NSSize(width: 360, height: 320)
    private var hasPosition = false
    /// Compact until the first message is sent; the height then follows the content.
    private var isCompact = true
    /// Placed above the cursor, so height changes keep the bottom edge.
    private var growsUp = false

    init(session: AskSession, openSettings: @escaping () -> Void) {
        self.session = session
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.fullSize.width, height: 160),
                   styleMask: [.resizable, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        title = "Peek"
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let content = PanelContentView()
        content.onAttachments = { [weak self] in self?.session.addAttachments($0) }
        content.onError = { [weak self] in self?.session.reportInputError($0) }
        let host = NSHostingView(rootView: ConversationView(session: session, openSettings: openSettings,
                                                           close: { [weak self] in self?.close() },
                                                           fitCompact: { [weak self] in self?.fitCompact(height: $0) },
                                                           expand: { [weak self] in self?.expand() }))
        host.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            host.topAnchor.constraint(equalTo: content.topAnchor),
            host.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        contentView = PanelContentView.background(around: content)
        invalidateShadow()
        delegate = self
        setAccessibilityLabel("Peek conversation")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present(anchor: CGRect?) {
        // A mode that sends right away has a message before the panel first appears.
        if !session.messages.isEmpty { expand() }
        contentView?.layoutSubtreeIfNeeded()
        if !hasPosition {
            // Place for the full height so expanding stays on screen and off the capture.
            let size = NSSize(width: frame.width, height: max(frame.height, Self.fullSize.height))
            let mouse = NSEvent.mouseLocation
            let origin = panelOrigin(anchor: anchor, panelSize: size,
                                     visibleFrames: NSScreen.screens.map(\.visibleFrame),
                                     primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0,
                                     mouseLocation: mouse)
            growsUp = origin.y > mouse.y
            setFrameOrigin(NSPoint(x: origin.x, y: growsUp ? origin.y : origin.y + size.height - frame.height))
            hasPosition = true
        }
        makeKeyAndOrderFront(nil)
    }

    private var visibleFrame: CGRect { (screen ?? NSScreen.main)?.visibleFrame ?? frame }

    private func fitCompact(height: CGFloat) {
        guard isCompact, height > 0 else { return }
        minSize = NSSize(width: Self.fullMinSize.width, height: height)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: height)
        // A resize from inside SwiftUI's layout pass is dropped, so apply it once the pass ends.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCompact, abs(self.frame.height - height) >= 0.5 else { return }
            self.setFrame(panelFrame(self.frame, height: height, growsUp: self.growsUp, within: self.visibleFrame),
                          display: true)
        }
    }

    /// Grows to full height away from the cursor, animating only when the panel is already on screen.
    private func expand() {
        guard isCompact else { return }
        isCompact = false
        minSize = Self.fullMinSize
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let target = panelFrame(frame, height: Self.fullSize.height, growsUp: growsUp, within: visibleFrame)
        guard isVisible else { return setFrame(target, display: true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.expandDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(target, display: true)
        }
    }

    override func close() {
        session.cancel()
        super.close()
        onClose?()
    }

    override func cancelOperation(_ sender: Any?) {}

    func windowDidBecomeKey(_ notification: Notification) {
        session.refreshSettings()
    }

    func windowDidResize(_ notification: Notification) {
        // The mask changes shape with the window, so the cached shadow has to be recomputed.
        invalidateShadow()
    }
}

/// The panel's content, which doubles as a drop target so a screenshot or file can be dragged
/// anywhere onto the conversation rather than only onto the composer.
@MainActor
final class PanelContentView: NSView {
    static let cornerRadius: CGFloat = 26

    var onAttachments: ([Capture.Content]) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    private let dropHighlight = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        dropHighlight.cornerRadius = Self.cornerRadius
        dropHighlight.borderWidth = 2
        dropHighlight.borderColor = NSColor.controlAccentColor.cgColor
        dropHighlight.isHidden = true
        layer?.addSublayer(dropHighlight)
        registerForDraggedTypes(AttachmentInput.dragTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        dropHighlight.frame = bounds
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        dropHighlight.borderColor = NSColor.controlAccentColor.cgColor
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard AttachmentInput.containsAttachments(sender.draggingPasteboard) else { return [] }
        dropHighlight.isHidden = false
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropHighlight.isHidden = true
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        dropHighlight.isHidden = true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropHighlight.isHidden = true
        return attachFiles(from: sender.draggingPasteboard)
    }

    /// Reads a drop into attachments, reporting unreadable files rather than failing silently.
    func attachFiles(from pasteboard: NSPasteboard) -> Bool {
        do {
            guard let contents = try AttachmentInput.attachments(from: pasteboard) else { return false }
            onAttachments(contents)
        } catch {
            onError(error.localizedDescription)
        }
        return true
    }

    /// Liquid Glass on macOS 26, the HUD material before it.
    static func background(around content: NSView) -> NSView {
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            // Clip to the rounded shape so the window shadow follows it, not the square frame.
            glass.wantsLayer = true
            glass.layer?.cornerRadius = cornerRadius
            glass.layer?.cornerCurve = .continuous
            glass.layer?.masksToBounds = true
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        // A stretchable mask, not a layer cornerRadius: the mask shapes the window itself, so the
        // shadow follows the rounded outline instead of leaving grey wedges in the corner notches.
        effect.maskImage = roundedMask(radius: cornerRadius)
        content.frame = effect.bounds
        effect.addSubview(content)
        return effect
    }

    /// A rounded rectangle stretched from its centre, the shape `maskImage` expects.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

struct PanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
                                                                  .activeAlways, .inVisibleRect], owner: self))
        }

        override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
        override func mouseMoved(with event: NSEvent) { updateCursor(event) }
        override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

        /// Controls sit on top of the handle, so the hand shows only where a click would start a drag.
        func showsHand(at windowPoint: NSPoint) -> Bool {
            window?.contentView?.hitTest(windowPoint) === self
        }

        private func updateCursor(_ event: NSEvent) {
            (showsHand(at: event.locationInWindow) ? NSCursor.openHand : NSCursor.arrow).set()
        }
    }
}
