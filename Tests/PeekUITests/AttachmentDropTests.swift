import AppKit
import PeekCore
import Testing
import UniformTypeIdentifiers
@testable import PeekUI

/// A stand-in for a live drag session, so drops can be exercised without a real drag.
private final class StubDrag: NSObject, @unchecked Sendable, NSDraggingInfo {
    let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard) { self.pasteboard = pasteboard }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { NSPoint(x: 10, y: 10) }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?,
                                classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

@MainActor
private func imageFile(type: UTType = .png) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("screen").appendingPathExtension(type.preferredFilenameExtension!)
    try composerImageData(type: type).write(to: url)
    return url
}

@MainActor
struct ScreenshotDropTests {
    @Test func rawImageDragIsClaimedByTheComposer() throws {
        let input = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        input.string = "keep my draft"
        var images: [Data] = []
        input.onAttachments = { images = $0.compactMap(\.imageData) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(try composerImageData(), forType: .png)
        let drag = StubDrag(pasteboard)
        // A plain NSTextView refuses raw image drags outright; the override has to claim them.
        #expect(input.draggingEntered(drag) == .copy)
        #expect(input.performDragOperation(drag))
        #expect(images.count == 1)
        try expectComposerPNG(images[0])
        #expect(input.string == "keep my draft")
    }

    @Test func draggedImageFileAttachesWithoutInsertingItsPath() throws {
        let url = try imageFile(type: .jpeg)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let input = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        var images: [Data] = []
        input.onAttachments = { images = $0.compactMap(\.imageData) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([url as NSURL])
        let drag = StubDrag(pasteboard)
        #expect(input.draggingEntered(drag) == .copy)
        #expect(input.performDragOperation(drag))
        #expect(images.count == 1)
        try expectComposerPNG(images[0])
        #expect(input.string.isEmpty)
    }

    @Test func draggedTextStillEditsTheDraft() throws {
        let input = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        var images: [Data] = []
        input.onAttachments = { images = $0.compactMap(\.imageData) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("dragged words", forType: .string)
        #expect(input.readSelection(from: pasteboard, type: .string))
        #expect(input.string == "dragged words")
        #expect(images.isEmpty)
    }

    @Test func draggedTextFileAttachesWithoutInsertingItsPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.txt")
        try Data("plain notes".utf8).write(to: url)
        let input = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        var attached: [Capture.Content] = []
        input.onAttachments = { attached = $0 }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([url as NSURL])
        let drag = StubDrag(pasteboard)
        #expect(input.draggingEntered(drag) == .copy)
        #expect(input.performDragOperation(drag))
        #expect(attached == [.text(name: "notes.txt", text: "plain notes")])
        #expect(input.string.isEmpty)
    }

    @Test func unsupportedFileDragIsNotClaimed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("archive.zip")
        try Data([80, 75, 3, 4]).write(to: url)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([url as NSURL])
        #expect(!AttachmentInput.containsAttachments(pasteboard))
    }

    @Test func panelBackgroundAcceptsImagesDroppedAnywhere() throws {
        let content = PanelContentView(frame: NSRect(x: 0, y: 0, width: 420, height: 500))
        var images: [Data] = []
        var errors: [String] = []
        content.onAttachments = { images = $0.compactMap(\.imageData) }
        content.onError = { errors.append($0) }
        #expect(content.registeredDraggedTypes.contains(.png))
        #expect(content.registeredDraggedTypes.contains(.fileURL))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(try composerImageData(type: .tiff), forType: .tiff)
        let drag = StubDrag(pasteboard)
        #expect(content.draggingEntered(drag) == .copy)
        #expect(content.performDragOperation(drag))
        #expect(images.count == 1)
        try expectComposerPNG(images[0])
        #expect(errors.isEmpty)
    }

    @Test func panelBackgroundIgnoresDragsItCannotRead() {
        let content = PanelContentView(frame: NSRect(x: 0, y: 0, width: 420, height: 500))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("just text", forType: .string)
        #expect(content.draggingEntered(StubDrag(pasteboard)).isEmpty)
    }

    @Test func unreadableDroppedImageReportsAnError() {
        let content = PanelContentView(frame: NSRect(x: 0, y: 0, width: 420, height: 500))
        var errors: [String] = []
        content.onError = { errors.append($0) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(Data("broken image".utf8), forType: .png)
        #expect(content.performDragOperation(StubDrag(pasteboard)))
        #expect(errors.count == 1)
    }

    @Test func panelIsShapedByAMaskSoItsShadowFollowsTheRoundedCorners() throws {
        let mask = PanelContentView.roundedMask(radius: PanelContentView.cornerRadius)
        let radius = PanelContentView.cornerRadius
        #expect(mask.size == NSSize(width: radius * 2 + 1, height: radius * 2 + 1))
        #expect(mask.resizingMode == .stretch)
        #expect(mask.capInsets.top == radius)
        #expect(mask.capInsets.left == radius)
        #expect(mask.capInsets.bottom == radius)
        #expect(mask.capInsets.right == radius)
        let content = PanelContentView(frame: NSRect(x: 0, y: 0, width: 420, height: 500))
        let background = PanelContentView.background(around: content)
        if #available(macOS 26, *) {
            let glass = try #require(background as? NSGlassEffectView)
            #expect(glass.cornerRadius == radius)
            #expect(glass.contentView === content)
            #expect(glass.layer?.cornerRadius == radius)
            #expect(glass.layer?.masksToBounds == true)
        } else {
            let effect = try #require(background as? NSVisualEffectView)
            #expect(effect.maskImage != nil)
            // A layer cornerRadius would clip drawing without reshaping the window, leaving the
            // window shadow squared off and grey in the corner notches.
            #expect(effect.layer?.cornerRadius ?? 0 == 0)
            #expect(content.superview === effect)
        }
    }
}
