import AppKit
import Testing
@testable import PeekCapture

@Test @MainActor func restoresTextAndOtherFormats() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let original = NSPasteboardItem()
    original.setString("Original text", forType: .string)
    let richText = Data("{\\rtf1 Original text}".utf8)
    original.setData(richText, forType: .rtf)
    #expect(pasteboard.writeObjects([original]))
    let snapshot = snapshotPasteboard(pasteboard)
    #expect(snapshot.string == "Original text")
    #expect(snapshot.changeCount == pasteboard.changeCount)
    #expect(copiedString(from: pasteboard, since: snapshot) == nil)

    pasteboard.clearContents()
    pasteboard.setString("Copied selection", forType: .string)
    #expect(copiedString(from: pasteboard, since: snapshot) == "Copied selection")
    restorePasteboard(snapshot, to: pasteboard)
    #expect(pasteboard.string(forType: .string) == "Original text")
    #expect(pasteboard.data(forType: .rtf) == richText)
}

@Test @MainActor func unchangedPasteboardIsUntouched() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("Stale clipboard text", forType: .string)
    let snapshot = snapshotPasteboard(pasteboard)
    #expect(copiedString(from: pasteboard, since: snapshot) == nil)
    restorePasteboard(snapshot, to: pasteboard)
    #expect(pasteboard.changeCount == snapshot.changeCount)
}

@Test @MainActor func sameTextCanBeANewSelection() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("Same text", forType: .string)
    let snapshot = snapshotPasteboard(pasteboard)
    pasteboard.clearContents()
    pasteboard.setString("Same text", forType: .string)
    #expect(copiedString(from: pasteboard, since: snapshot) == "Same text")
}

@Test @MainActor func emptyCopyAndEmptyOriginal() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    let snapshot = snapshotPasteboard(pasteboard)
    pasteboard.clearContents()
    pasteboard.setString("", forType: .string)
    #expect(copiedString(from: pasteboard, since: snapshot) == nil)
    pasteboard.setString("Copied", forType: .string)
    restorePasteboard(snapshot, to: pasteboard)
    #expect(pasteboard.string(forType: .string) == nil)
    #expect(pasteboard.pasteboardItems?.isEmpty != false)
}

@Test @MainActor func restoresMultipleNonTextItems() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let type = NSPasteboard.PasteboardType("com.peek.tests.binary")
    let originals = [Data([0, 1, 2]), Data([3, 4, 5])]
    let items = originals.map { data in
        let item = NSPasteboardItem()
        item.setData(data, forType: type)
        return item
    }
    #expect(pasteboard.writeObjects(items))
    let snapshot = snapshotPasteboard(pasteboard)
    #expect(snapshot.string == nil)
    pasteboard.clearContents()
    pasteboard.setString("Copied text", forType: .string)
    restorePasteboard(snapshot, to: pasteboard)
    let restored = try #require(pasteboard.pasteboardItems)
    #expect(restored.compactMap { $0.data(forType: type) } == originals)
    #expect(pasteboard.string(forType: .string) == nil)
}
