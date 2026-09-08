import Foundation
import PeekCore

internal struct CLIRequestDirectory {
    let url: URL
    let images: [URL]
    let transcript: String

    init(request: AIRequest) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("peek-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            var images: [URL] = []
            var messages: [[String: Any]] = []
            for (turn, message) in request.messages.enumerated() {
                var screenshots: [[String: Any]] = []
                for (index, capture) in message.captures.enumerated() {
                    let data = switch capture.content { case .image(let png): png }
                    let image = directory.appendingPathComponent("turn-\(turn + 1)-capture-\(index + 1).png")
                    try data.write(to: image, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: image.path)
                    images.append(image)
                    screenshots.append(["attachment": images.count, "path": image.path])
                }
                messages.append(["role": message.role.rawValue, "text": message.text, "screenshots": screenshots])
            }
            let data = try JSONSerialization.data(withJSONObject: messages, options: [.sortedKeys, .withoutEscapingSlashes])
            transcript = "Continue this conversation by answering the latest user message. Assistant entries are previous answers. Each screenshot belongs to its containing message; attachment numbers identify images in order.\n\nConversation JSON:\n" + String(decoding: data, as: UTF8.self)
            self.images = images
            url = directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
