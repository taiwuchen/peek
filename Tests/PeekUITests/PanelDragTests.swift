import AppKit
import Testing
@testable import PeekUI

@MainActor
private final class DragRecordingPanel: NSPanel {
    var dragEvent: NSEvent?

    override func performDrag(with event: NSEvent) { dragEvent = event }
}

@Test @MainActor func customHeaderStartsNativeWindowDragging() throws {
    let panel = DragRecordingPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    let handle = PanelDragHandle.DragView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    panel.contentView = handle
    let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10),
                                               modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                               context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    handle.mouseDown(with: event)
    #expect(panel.dragEvent === event)
}

@Test @MainActor func dragHandShowsOnlyOutsideControls() {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40), styleMask: .borderless,
                        backing: .buffered, defer: false)
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
    let handle = PanelDragHandle.DragView(frame: content.bounds)
    let button = NSButton(frame: NSRect(x: 160, y: 5, width: 30, height: 30))
    content.addSubview(handle)
    content.addSubview(button)
    panel.contentView = content
    #expect(handle.showsHand(at: NSPoint(x: 80, y: 20)))
    #expect(!handle.showsHand(at: NSPoint(x: 175, y: 20)))
}
