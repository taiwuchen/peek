import Foundation
import PeekCore

struct StubSelectionReader: SelectionReader {
    func readSelection() async throws -> Capture {
        Capture(content: .text("Peek keeps answers beside the content you are working with."),
                anchor: nil, sourceBundleID: nil)
    }
}

struct StubRegionCapturer: ScreenRegionCapturer {
    func captureRegion() async throws -> Capture { throw CaptureError.cancelled }
}

struct EchoProvider: AIProvider {
    let id = ProviderID.anthropicAPI
    let displayName = "Echo Preview"
    let supportsImages = true

    func availability() async -> ProviderAvailability { .ready }
    func models() async throws -> [AIModel] { [AIModel(id: "echo", displayName: "Echo")] }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for word in request.question.split(separator: " ") {
                        try await Task.sleep(for: .milliseconds(250))
                        continuation.yield(String(word) + " ")
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
