import AppKit
import ApplicationServices
import PeekCore

public struct AccessibilitySelectionReader: SelectionReader {
    @MainActor private static var isReading = false

    public init() {}

    @MainActor
    public func readSelection() async throws -> Capture {
        guard Permissions.accessibilityGranted else { throw CaptureError.accessibilityPermissionDenied }
        guard !Self.isReading else { throw CaptureError.failed("A selection read is already in progress.") }
        Self.isReading = true
        defer { Self.isReading = false }
        guard !Task.isCancelled else { throw CaptureError.cancelled }

        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let element = focusedElement(),
           let text = attribute(kAXSelectedTextAttribute, of: element) as? String, !text.isEmpty {
            return Capture(content: .text(text), anchor: selectedBounds(of: element), sourceBundleID: sourceBundleID)
        }

        let mouse = CaptureCoordinates.topLeft(NSEvent.mouseLocation, primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0)
        let text = try await copySelection()
        return Capture(content: .text(text), anchor: CGRect(origin: mouse, size: CGSize(width: 1, height: 1)), sourceBundleID: sourceBundleID)
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        guard let application = attribute(kAXFocusedApplicationAttribute, of: system),
              CFGetTypeID(application) == AXUIElementGetTypeID() else { return nil }
        let focusedApplication = application as! AXUIElement
        guard let element = attribute(kAXFocusedUIElementAttribute, of: focusedApplication),
              CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        return (element as! AXUIElement)
    }

    private func selectedBounds(of element: AXUIElement) -> CGRect? {
        guard let range = attribute(kAXSelectedTextRangeAttribute, of: element) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var bounds = CGRect.zero
        guard AXValueGetType(axValue) == .cgRect, AXValueGetValue(axValue, .cgRect, &bounds) else { return nil }
        return bounds
    }

    @MainActor
    private func copySelection() async throws -> String {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        defer { restorePasteboard(snapshot, to: pasteboard) }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false) else {
            throw CaptureError.failed("Could not create the copy keyboard event.")
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
        repeat {
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                throw CaptureError.cancelled
            }
            if let string = copiedString(from: pasteboard, since: snapshot) { return string }
        } while ContinuousClock.now < deadline
        throw CaptureError.noSelection
    }
}
