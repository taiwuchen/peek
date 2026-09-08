import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum ScreenshotInput {
    static func pngImages(from pasteboard: NSPasteboard) throws -> [Data]? {
        var images: [Data] = []
        for item in pasteboard.pasteboardItems ?? [] {
            let preferredTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init(UTType.jpeg.identifier)]
            let imageTypes = preferredTypes + item.types.filter {
                UTType($0.rawValue)?.conforms(to: .image) == true && !preferredTypes.contains($0)
            }
            if let type = imageTypes.first(where: { item.types.contains($0) }) {
                guard let data = item.data(forType: type) else { throw InputError.invalidImage }
                images.append(try png(data))
            } else if item.types.contains(.fileURL) {
                guard let value = item.string(forType: .fileURL), let url = URL(string: value) else {
                    throw InputError.invalidImage
                }
                images.append(contentsOf: try pngImages(from: [url]))
            }
        }
        return images.isEmpty ? nil : images
    }

    static func pngImages(from urls: [URL]) throws -> [Data] {
        try urls.map { url in
            guard url.isFileURL else { throw InputError.invalidImage }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw InputError.unreadableFile
            }
            return try png(data)
        }
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
        case unreadableFile

        var errorDescription: String? {
            switch self {
            case .invalidImage: "Could not read this image. Choose a PNG, JPEG, or TIFF image."
            case .unreadableFile: "Could not open this image file. Try choosing it again."
            }
        }
    }
}
