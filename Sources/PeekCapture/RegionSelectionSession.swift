import AppKit
import PeekCore

@MainActor
final class RegionSelectionSession {
    private var windows: [RegionOverlayPanel] = []
    private var continuation: CheckedContinuation<SelectedRegion, any Error>?
    private var cursorPushed = false
    private(set) var windowIDs: Set<CGWindowID> = []

    func select() async throws -> SelectedRegion {
        try await withCheckedThrowingContinuation { continuation in
            guard !Task.isCancelled else {
                continuation.resume(throwing: CaptureError.cancelled)
                return
            }
            let screens = NSScreen.screens
            guard let primary = screens.first else {
                continuation.resume(throwing: CaptureError.failed("No displays are available."))
                return
            }
            self.continuation = continuation
            for screen in screens {
                guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                let screenFrame = screen.frame
                let scale = screen.backingScaleFactor
                let displayID = displayNumber.uint32Value
                let panel = RegionOverlayPanel(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.level = .screenSaver
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.animationBehavior = .none
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.acceptsMouseMovedEvents = true
                let view = RegionOverlayView(frame: CGRect(origin: .zero, size: screenFrame.size))
                view.onFinish = { [weak self] rect in
                    guard let rect, rect.width > 0, rect.height > 0 else {
                        self?.cancel()
                        return
                    }
                    self?.finish(.success(SelectedRegion(rect: rect, screenFrame: screenFrame, primaryScreenHeight: primary.frame.height, displayID: displayID, scale: scale)))
                }
                panel.contentView = view
                panel.makeFirstResponder(view)
                windows.append(panel)
                panel.orderFrontRegardless()
                windowIDs.insert(CGWindowID(panel.windowNumber))
            }
            guard !windows.isEmpty else {
                finish(.failure(CaptureError.failed("No displays are available.")))
                return
            }
            NSCursor.crosshair.push()
            cursorPushed = true
            let target = windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows[0]
            target.makeKey()
        }
    }

    func cancel() {
        finish(.failure(CaptureError.cancelled))
    }

    private func finish(_ result: Result<SelectedRegion, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        for window in windows {
            (window.contentView as? RegionOverlayView)?.onFinish = nil
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        continuation.resume(with: result)
    }
}

private final class RegionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class RegionOverlayView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?
    private var cursorTracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        cursorTracking = area
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseEntered(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = CaptureCoordinates.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        onFinish?(CaptureCoordinates.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) }
    }

    override func cancelOperation(_ sender: Any?) { onFinish?(nil) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let dimming = NSBezierPath(rect: bounds)
        if let selection, selection.width > 0, selection.height > 0 {
            dimming.appendRect(selection)
            dimming.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.3).setFill()
        dimming.fill()
        if let selection, selection.width > 0, selection.height > 0 {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
    }
}
