import Foundation
import PeekCore

public struct ClaudeCLIProvider: AIProvider {
    public let id = ProviderID.claudeCLI
    public let displayName = "Claude Code (subscription)"
    public let supportsImages = true
    private let settings: any SettingsStore

    public init(settings: any SettingsStore) {
        self.settings = settings
    }

    public func availability() async -> ProviderAvailability {
        guard let path = await CLILocator().locate("claude", override: settings.load().claudePath) else { return .cliNotInstalled }
        do {
            let output = try await Subprocess(executable: path, arguments: ["auth", "status", "--json"], timeout: 10).output()
            guard let value = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
                  let loggedIn = value["loggedIn"] as? Bool else { return .unavailable("Invalid Claude login status") }
            return loggedIn ? .ready : .cliNotLoggedIn
        } catch ProviderError.processFailed {
            return .cliNotLoggedIn
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    public func models() async throws -> [AIModel] {
        [AIModel(id: "default", displayName: "Default (plan default)"), AIModel(id: "opus", displayName: "Opus"),
         AIModel(id: "sonnet", displayName: "Sonnet"), AIModel(id: "haiku", displayName: "Haiku")]
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let path = await CLILocator().locate("claude", override: settings.load().claudePath) else {
                        throw ProviderError.notAvailable(.cliNotInstalled)
                    }
                    try Task.checkCancellation()
                    let directory = try CLIRequestDirectory(request: request)
                    defer { directory.remove() }
                    var arguments = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                                     "--model", request.model, "--system-prompt", AIRequest.systemPrompt,
                                     "--safe-mode", "--no-session-persistence"]
                    var prompt = request.userText
                    if let image = directory.image {
                        arguments += ["--tools", "Read", "--allowedTools", "Read"]
                        prompt = "View the image at \(image.path), then: \(prompt)"
                    } else {
                        arguments += ["--tools", ""]
                    }
                    let process = Subprocess(executable: path, arguments: arguments, input: Data(prompt.utf8), directory: directory.url)
                    var events = ClaudeCLIEvents()
                    for try await line in process.lines() {
                        try Task.checkCancellation()
                        if let text = try events.text(from: line), !text.isEmpty { continuation.yield(text) }
                    }
                    try Task.checkCancellation()
                } catch is CancellationError {
                    continuation.finish(throwing: ProviderError.cancelled)
                    return
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
