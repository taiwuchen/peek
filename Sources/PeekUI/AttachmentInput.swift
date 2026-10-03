import AppKit
import ImageIO
import PDFKit
import PeekCore
import UniformTypeIdentifiers

@MainActor
enum AttachmentInput {
    /// Pasteboard types worth registering as drag destinations for attachments.
    static let dragTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init(UTType.jpeg.identifier), .fileURL]

    /// Whether a drag or paste carries something `attachments(from:)` can read.
    /// Used to decide whether to claim a drag before reading it.
    static func containsAttachments(_ pasteboard: NSPasteboard) -> Bool {
        for item in pasteboard.pasteboardItems ?? [] {
            if item.types.contains(where: { UTType($0.rawValue)?.conforms(to: .image) == true }) { return true }
            if let value = item.string(forType: .fileURL), let url = URL(string: value), isSupported(url) {
                return true
            }
        }
        return false
    }

    static func attachments(from pasteboard: NSPasteboard) throws -> [Capture.Content]? {
        var contents: [Capture.Content] = []
        for item in pasteboard.pasteboardItems ?? [] {
            let preferredTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init(UTType.jpeg.identifier)]
            let imageTypes = preferredTypes + item.types.filter {
                UTType($0.rawValue)?.conforms(to: .image) == true && !preferredTypes.contains($0)
            }
            if let type = imageTypes.first(where: { item.types.contains($0) }) {
                guard let data = item.data(forType: type) else { throw InputError.invalidImage }
                contents.append(.image(try png(data)))
            } else if item.types.contains(.fileURL) {
                guard let value = item.string(forType: .fileURL), let url = URL(string: value) else {
                    throw InputError.unreadableFile
                }
                contents.append(contentsOf: try attachments(from: [url]))
            }
        }
        return contents.isEmpty ? nil : contents
    }

    static func attachments(from urls: [URL]) throws -> [Capture.Content] {
        try urls.map { url in
            guard url.isFileURL else { throw InputError.unreadableFile }
            guard let type = UTType(filenameExtension: url.pathExtension), isSupported(url) else {
                throw InputError.unsupportedFile
            }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw InputError.unreadableFile
            }
            if type.conforms(to: .image) { return .image(try png(data)) }
            if type.conforms(to: .pdf) {
                guard let document = PDFDocument(data: data), !document.isLocked else { throw InputError.invalidPDF }
                return .pdf(name: url.lastPathComponent, data: data)
            }
            guard let text = String(data: data, encoding: .utf8) else { throw InputError.invalidText }
            return .text(name: url.lastPathComponent, text: text)
        }
    }

    private static func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf) || type.conforms(to: .text)
    }

    private static func png(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw InputError.invalidImage
        }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else {
            throw InputError.invalidImage
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw InputError.invalidImage }
        return result as Data
    }

    private enum InputError: LocalizedError {
        case invalidImage
        case invalidPDF
        case invalidText
        case unreadableFile
        case unsupportedFile

        var errorDescription: String? {
            switch self {
            case .invalidImage: "Could not read this image. Choose a PNG, JPEG, or TIFF image."
            case .invalidPDF: "Could not read this PDF. It may be damaged or password protected."
            case .invalidText: "Could not read this text file. Save it as UTF-8 and try again."
            case .unreadableFile: "Could not open this file. Try choosing it again."
            case .unsupportedFile: "Peek can attach images, PDFs, and text files."
            }
        }
    }
}
