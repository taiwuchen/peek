import AppKit
import ImageIO
import PDFKit
import PeekCore
import Testing
import UniformTypeIdentifiers
@testable import PeekUI

@MainActor
struct AttachmentInputTests {
    @Test(arguments: [UTType.png, .tiff, .jpeg])
    func clipboardImagePreservesResolution(type: UTType) throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(try composerImageData(type: type), forType: .init(type.identifier))
        let images = try #require(try AttachmentInput.attachments(from: pasteboard)).compactMap(\.imageData)
        #expect(images.count == 1)
        try expectComposerPNG(images[0])
    }

    @Test func clipboardRepresentationsAreNotDuplicated() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setData(try composerImageData(), forType: .png)
        first.setData(try composerImageData(type: .tiff), forType: .tiff)
        first.setString("file:///does-not-exist.png", forType: .fileURL)
        let second = NSPasteboardItem()
        second.setData(try composerImageData(), forType: .png)
        pasteboard.writeObjects([first, second])
        #expect(try AttachmentInput.attachments(from: pasteboard)?.count == 2)
    }

    @Test func copiedImageFileAndChosenFilesConvertToPNG() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = [directory.appendingPathComponent("screen.tiff"), directory.appendingPathComponent("screen.jpg")]
        try composerImageData(type: .tiff).write(to: urls[0])
        try composerImageData(type: .jpeg).write(to: urls[1])
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects(urls as [NSURL])
        let pasted = try #require(try AttachmentInput.attachments(from: pasteboard)).compactMap(\.imageData)
        let chosen = try AttachmentInput.attachments(from: urls).compactMap(\.imageData)
        #expect(pasted.count == 2)
        #expect(chosen.count == 2)
        for data in pasted + chosen { try expectComposerPNG(data) }
    }

    @Test(arguments: ["ordinary text", "https://example.com/image.png", "file:///private/image.png"])
    func textDoesNotReadFiles(text: String) throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString(text, forType: .string)
        #expect(try AttachmentInput.attachments(from: pasteboard) == nil)
    }

    @Test func invalidClipboardImageThrows() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(Data("not an image".utf8), forType: .png)
        #expect(throws: (any Error).self) { try AttachmentInput.attachments(from: pasteboard) }
    }

    @Test func pdfAndTextFilesAttachWithTheirNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let pdf = try #require(document.dataRepresentation())
        let urls = ["report.pdf", "notes.md", "data.json"].map { directory.appendingPathComponent($0) }
        try pdf.write(to: urls[0])
        try Data("# Notes".utf8).write(to: urls[1])
        try Data("{\"a\":1}".utf8).write(to: urls[2])
        let contents = try AttachmentInput.attachments(from: urls)
        #expect(contents == [.pdf(name: "report.pdf", data: pdf), .text(name: "notes.md", text: "# Notes"),
                             .text(name: "data.json", text: "{\"a\":1}")])
    }

    @Test func lockedPDFThrows() throws {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let locked = try #require(document.dataRepresentation(options: [PDFDocumentWriteOption.userPasswordOption: "secret",
                                                                       PDFDocumentWriteOption.ownerPasswordOption: "owner"]))
        #expect(PDFDocument(data: locked)?.isLocked == true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try locked.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self) { try AttachmentInput.attachments(from: [url]) }
    }

    @Test(arguments: [("archive.zip", Data([80, 75, 3, 4])), ("broken.pdf", Data("not a pdf".utf8)),
                      ("binary.txt", Data([0xFF, 0xFE, 0xFD]))])
    func unsupportedDamagedOrNonUTF8FilesThrow(name: String, data: Data) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self) { try AttachmentInput.attachments(from: [url]) }
    }

    @Test func invalidFileAndRemoteURLThrow() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data("not an image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self) { try AttachmentInput.attachments(from: [url]) }
        #expect(throws: (any Error).self) {
            try AttachmentInput.attachments(from: [URL(string: "https://example.com/image.png")!])
        }
    }
}

extension Capture.Content {
    var imageData: Data? {
        if case .image(let data) = self { data } else { nil }
    }
}

func composerImageData(type: UTType = .png) throws -> Data {
    let context = try #require(CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 8,
                                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

func expectComposerPNG(_ data: Data) throws {
    #expect(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 24)
    #expect(image.height == 16)
}
