import Foundation
import PeekCore

public struct CodexCLIProvider: AIProvider {
    public let id = ProviderID.codexCLI
    public let displayName = "Codex (ChatGPT subscription)"
    public let supportsImages = true
    private let settings: any SettingsStore

    public init(settings: any SettingsStore) {
        self.settings = settings
    }

    public func availability() async -> ProviderAvailability {
        guard let path = await CLILocator().locate("codex", override: settings.load().codexPath) else { return .cliNotInstalled }
        do {
            let output = try await Subprocess(executable: path, arguments: ["login", "status"], timeout: 10).output()
            return output.lowercased().contains("not logged in") ? .cliNotLoggedIn : .ready
        } catch ProviderError.processFailed {
            return .cliNotLoggedIn
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    public func models() async throws -> [AIModel] {
        guard let path = await CLILocator().locate("codex", override: settings.load().codexPath) else {
            throw ProviderError.notAvailable(.cliNotInstalled)
        }
        do {
            let output = try await Subprocess(executable: path, arguments: ["debug", "models"], timeout: 10).output()
            let catalog = try JSONDecoder().decode(ModelCatalog.self, from: Data(output.utf8))
            let models = catalog.models.filter { $0.visibility == "list" }.map { AIModel(id: $0.slug, displayName: $0.display_name) }
            if !models.isEmpty { return models }
        } catch is CancellationError {
            try Task.checkCancellation()
        } catch {}
        return [AIModel(id: "gpt-5.6-sol", displayName: "GPT-5.6 Sol"), AIModel(id: "gpt-5.5", displayName: "GPT-5.5")]
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let path = await CLILocator().locate("codex", override: settings.load().codexPath) else {
                        throw ProviderError.notAvailable(.cliNotInstalled)
                    }
                    try Task.checkCancellation()
                    let directory = try CLIRequestDirectory(request: request)
                    defer { directory.remove() }
                    var arguments = ["exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only",
                                     "--ephemeral", "--ignore-user-config", "-m", request.model]
                    for image in directory.images { arguments += ["-i", image.path] }
                    arguments += ["-"]
                    let prompt = AIRequest.systemPrompt + "\n\n" + directory.transcript
                    let process = Subprocess(executable: path, arguments: arguments, input: Data(prompt.utf8), directory: directory.url)
                    let events = CodexCLIEvents()
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

    private struct ModelCatalog: Decodable {
        let models: [Model]

        struct Model: Decodable {
            let slug: String
            let display_name: String
            let visibility: String
        }
    }
}
