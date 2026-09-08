import AppKit
import SwiftUI
import Testing
@testable import PeekUI

@MainActor
struct ChatComposerTests {
    @Test func plainTextPasteReplacesSelection() {
        let input = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 100))
        input.isRichText = false
        input.string = "hello draft"
        input.setSelectedRange(NSRange(location: 6, length: 5))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("world", forType: .string)
        #expect(input.readSelection(from: pasteboard, type: .string))
        #expect(input.string == "hello world")
    }

    @Test func imagePastePreservesDraftAndSelection() throws {
        let input = ComposerTextView(frame: .zero)
        input.string = "keep my draft"
        let selection = NSRange(location: 5, length: 2)
        input.setSelectedRange(selection)
        var images: [Data] = []
        input.onImages = { images = $0 }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(try composerImageData(), forType: .png)
        #expect(input.readSelection(from: pasteboard, type: .png))
        #expect(images.count == 1)
        #expect(input.string == "keep my draft")
        #expect(input.selectedRange() == selection)
    }

    @Test func invalidImageReportsErrorWithoutPastingFallbackText() {
        let input = ComposerTextView(frame: .zero)
        input.string = "keep my draft"
        input.setSelectedRange(NSRange(location: 0, length: 13))
        var error: String?
        input.onError = { error = $0 }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(Data("broken image".utf8), forType: .png)
        pasteboard.setString("fallback text", forType: .string)
        #expect(input.readSelection(from: pasteboard, type: .png))
        #expect(error?.isEmpty == false)
        #expect(input.string == "keep my draft")
    }

    @Test func enterSubmitsAndShiftEnterEdits() throws {
        let input = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 100))
        input.string = "hello"
        input.setSelectedRange(NSRange(location: 5, length: 0))
        var submissions = 0
        input.onSubmit = { submissions += 1 }
        let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                timestamp: 0, windowNumber: 0, context: nil,
                                                characters: "\r", charactersIgnoringModifiers: "\r",
                                                isARepeat: false, keyCode: 36))
        let shiftEnter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift],
                                                     timestamp: 0, windowNumber: 0, context: nil,
                                                     characters: "\r", charactersIgnoringModifiers: "\r",
                                                     isARepeat: false, keyCode: 36))
        input.keyDown(with: enter)
        #expect(submissions == 1)
        #expect(input.string == "hello")
        input.keyDown(with: shiftEnter)
        #expect(input.string == "hello\n")
        #expect(submissions == 1)
    }

    @Test func imageAndFileTypesAreAvailableToNativePaste() {
        let input = ComposerTextView(frame: .zero)
        #expect(input.readablePasteboardTypes.contains(.png))
        #expect(input.readablePasteboardTypes.contains(.fileURL))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("plain text", forType: .string)
        #expect(pasteboard.availableType(from: input.readablePasteboardTypes) != nil)
    }

    @Test func hostedComposerTakesInitialFocus() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
                             styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        defer { window.close() }
        let host = NSHostingView(rootView: ChatComposer(text: .constant("draft"), onSubmit: {}, onImages: { _ in }, onError: { _ in }))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        #expect(window.firstResponder is ComposerTextView)
    }

    @Test func composerHeightGrowsAndCaps() {
        func height(_ text: String) -> CGFloat {
            let host = NSHostingView(rootView: ChatComposer(text: .constant(text), onSubmit: {}, onImages: { _ in }, onError: { _ in })
                .frame(width: 240))
            return host.fittingSize.height
        }
        let emptyHeight = height("")
        let multilineHeight = height("first\nsecond\n")
        let longHeight = height(String(repeating: "a line\n", count: 20))
        #expect(emptyHeight == 34)
        #expect(multilineHeight > emptyHeight)
        #expect(longHeight == 100)
    }
}
