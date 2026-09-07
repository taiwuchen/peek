import Foundation
import PeekCore

public struct AnthropicAPIProvider: AIProvider {
    public let id = ProviderID.anthropicAPI
    public let displayName = "Anthropic API"
    public let supportsImages = true
    private let credentials: any CredentialStore
    private let session: URLSession

    public init(credentials: any CredentialStore, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    public func availability() async -> ProviderAvailability {
        (try? HTTP.apiKey(credentials, for: id)) == nil ? .needsAPIKey : .ready
    }

    public func models() async throws -> [AIModel] {
        do {
            let request = try HTTP.request(url: URL(string: "https://api.anthropic.com/v1/models")!, headers: headers())
            let data = try await HTTP.data(for: request, session: session)
            let response = try JSONDecoder().decode(ModelList.self, from: data)
            guard !response.data.isEmpty else { return Self.fallbackModels }
            return response.data.sorted {
                if $0.created_at != $1.created_at { return ($0.created_at ?? "") > ($1.created_at ?? "") }
                let families = ["opus", "sonnet", "haiku"]
                let lhsRank = families.firstIndex(where: $0.id.contains) ?? families.count
                let rhsRank = families.firstIndex(where: $1.id.contains) ?? families.count
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return $0.id.compare($1.id, options: .numeric) == .orderedDescending
            }.map { AIModel(id: $0.id, displayName: $0.display_name) }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw ProviderError.cancelled
            }
            return Self.fallbackModels
        }
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        HTTP.stream(session: session, request: {
            var content: [[String: Any]] = []
            if case .image(let png)? = request.capture?.content {
                content.append(["type": "image", "source": [
                    "type": "base64", "media_type": "image/png", "data": png.base64EncodedString(),
                ]])
            }
            content.append(["type": "text", "text": request.userText])
            return try HTTP.request(url: URL(string: "https://api.anthropic.com/v1/messages")!, headers: headers(), body: [
                "model": request.model, "max_tokens": 8192, "stream": true,
                "system": AIRequest.systemPrompt, "messages": [["role": "user", "content": content]],
            ])
        }, decode: Self.decode)
    }

    private func headers() throws -> [String: String] {
        ["x-api-key": try HTTP.apiKey(credentials, for: id), "anthropic-version": "2023-06-01", "Content-Type": "application/json"]
    }

    private static func decode(_ event: SSEEvent) throws -> HTTP.StreamEvent {
        let object = try HTTP.object(event)
        if event.event == "error" || object["type"] as? String == "error" {
            let error = object["error"] as? [String: Any]
            throw ProviderError.malformedResponse(error?["message"] as? String ?? "Anthropic stream failed.")
        }
        guard let type = object["type"] as? String else {
            throw ProviderError.malformedResponse("Anthropic event is missing its type.")
        }
        switch type {
        case "content_block_delta":
            guard let delta = object["delta"] as? [String: Any], let deltaType = delta["type"] as? String else {
                throw ProviderError.malformedResponse("Anthropic event is missing its delta.")
            }
            guard deltaType == "text_delta" else { return .text([]) }
            guard let text = delta["text"] as? String else {
                throw ProviderError.malformedResponse("Anthropic text delta is missing its text.")
            }
            return .text([text])
        case "message_stop": return .finished
        default: return .text([])
        }
    }

    private struct ModelList: Decodable {
        let data: [Model]
        struct Model: Decodable {
            let id: String
            let display_name: String
            let created_at: String?
        }
    }

    private static let fallbackModels = [
        AIModel(id: "claude-opus-5", displayName: "Claude Opus 5"),
        AIModel(id: "claude-sonnet-5", displayName: "Claude Sonnet 5"),
        AIModel(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5"),
    ]
}
