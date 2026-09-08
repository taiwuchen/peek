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
        let effect = PanelContentView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        // A stretchable mask, not a layer cornerRadius: the mask shapes the window itself, so the
        // shadow follows the rounded outline instead of leaving grey wedges in the corner notches.
        effect.maskImage = PanelContentView.roundedMask(radius: PanelContentView.cornerRadius)
        effect.onImages = { [weak self] in self?.session.addScreenshots($0) }
        effect.onError = { [weak self] in self?.session.reportInputError($0) }
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
        invalidateShadow()
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

    func windowDidResize(_ notification: Notification) {
        // The mask changes shape with the window, so the cached shadow has to be recomputed.
        invalidateShadow()
    }
}

/// The panel's rounded background, which doubles as a drop target so a screenshot can be dragged
/// anywhere onto the conversation rather than only onto the composer.
@MainActor
final class PanelContentView: NSVisualEffectView {
    static let cornerRadius: CGFloat = 14

    var onImages: ([Data]) -> Void = { _ in }
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
        registerForDraggedTypes(ScreenshotInput.dragTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        dropHighlight.frame = bounds
    }

    override func updateLayer() {
        super.updateLayer()
        dropHighlight.borderColor = NSColor.controlAccentColor.cgColor
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard ScreenshotInput.containsImages(sender.draggingPasteboard) else { return [] }
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
        return attachImages(from: sender.draggingPasteboard)
    }

    /// Reads a drop into screenshots, reporting unreadable images rather than failing silently.
    func attachImages(from pasteboard: NSPasteboard) -> Bool {
        do {
            guard let images = try ScreenshotInput.pngImages(from: pasteboard) else { return false }
            onImages(images)
        } catch {
            onError(error.localizedDescription)
        }
        return true
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
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}
