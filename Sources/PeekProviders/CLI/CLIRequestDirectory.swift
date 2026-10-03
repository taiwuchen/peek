import Foundation
import PDFKit
import PeekCore

internal struct CLIRequestDirectory {
    let url: URL
    let images: [URL]
    /// PDFs written for the CLI to read; empty when PDFs are inlined as text.
    let pdfs: [URL]
    let transcript: String

    /// `inlinesPDFs` sends extracted PDF text for CLIs that cannot read PDF files.
    init(request: AIRequest, inlinesPDFs: Bool = false) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("peek-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            var images: [URL] = []
            var pdfs: [URL] = []
            var messages: [[String: Any]] = []
            for (turn, message) in request.messages.enumerated() {
                var screenshots: [[String: Any]] = []
                var files: [[String: Any]] = []
                for (index, capture) in message.captures.enumerated() {
                    switch capture.content {
                    case .image(let png):
                        let image = directory.appendingPathComponent("turn-\(turn + 1)-capture-\(index + 1).png")
                        try Self.write(png, to: image)
                        images.append(image)
                        screenshots.append(["attachment": images.count, "path": image.path])
                    case .pdf(let name, let data) where inlinesPDFs:
                        let text = PDFDocument(data: data)?.string ?? ""
                        files.append(["name": name, "text": text.isEmpty ? "(This PDF has no extractable text.)" : text])
                    case .pdf(let name, let data):
                        let pdf = directory.appendingPathComponent("turn-\(turn + 1)-file-\(index + 1).pdf")
                        try Self.write(data, to: pdf)
                        pdfs.append(pdf)
                        files.append(["name": name, "path": pdf.path])
                    case .text(let name, let text):
                        files.append(["name": name, "text": text])
                    }
                }
                var entry: [String: Any] = ["role": message.role.rawValue, "text": message.text, "screenshots": screenshots]
                if !files.isEmpty { entry["files"] = files }
                messages.append(entry)
            }
            let data = try JSONSerialization.data(withJSONObject: messages, options: [.sortedKeys, .withoutEscapingSlashes])
            transcript = "Continue this conversation by answering the latest user message. Assistant entries are previous answers. Each screenshot and file belongs to its containing message; attachment numbers identify images in order.\n\nConversation JSON:\n" + String(decoding: data, as: UTF8.self)
            self.images = images
            self.pdfs = pdfs
            url = directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    private static func write(_ data: Data, to file: URL) throws {
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
