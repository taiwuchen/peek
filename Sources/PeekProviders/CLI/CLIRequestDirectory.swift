import Foundation
import PeekCore

internal struct CLIRequestDirectory {
    let url: URL
    let image: URL?

    init(request: AIRequest) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("peek-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            if case .image(let data)? = request.capture?.content {
                let image = directory.appendingPathComponent("capture.png")
                try data.write(to: image, options: .atomic)
                self.image = image
            } else {
                image = nil
            }
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
