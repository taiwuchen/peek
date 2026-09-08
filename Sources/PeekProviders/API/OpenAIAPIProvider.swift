import Foundation
import PeekCore

public struct OpenAIAPIProvider: AIProvider {
    public let id = ProviderID.openAIAPI
    public let displayName = "OpenAI API"
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
            let request = try HTTP.request(url: URL(string: "https://api.openai.com/v1/models")!, headers: headers())
            let data = try await HTTP.data(for: request, session: session)
            let response = try JSONDecoder().decode(ModelList.self, from: data)
            let excluded = ["realtime", "audio", "tts", "transcribe", "image", "embedding", "moderation"]
            let models = response.data.filter { model in
                (model.id.hasPrefix("gpt-") || model.id.hasPrefix("o")) && !excluded.contains(where: model.id.contains)
            }.sorted {
                if $0.created != $1.created { return ($0.created ?? 0) > ($1.created ?? 0) }
                return $0.id.compare($1.id, options: .numeric) == .orderedDescending
            }.map { model in
                AIModel(id: model.id, displayName: model.id.hasPrefix("gpt-") ? "GPT-" + model.id.dropFirst(4) : model.id)
            }
            return models.isEmpty ? Self.fallbackModels : models
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw ProviderError.cancelled
            }
            return Self.fallbackModels
        }
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        HTTP.stream(session: session, request: {
            let input: [[String: Any]] = request.messages.map { message in
                var content: [[String: Any]] = message.captures.map { capture in
                    let png = switch capture.content { case .image(let data): data }
                    return ["type": "input_image", "image_url": "data:image/png;base64,\(png.base64EncodedString())"]
                }
                if !message.text.isEmpty { content.append(["type": "input_text", "text": message.text]) }
                return ["role": message.role.rawValue, "content": content]
            }
            return try HTTP.request(url: URL(string: "https://api.openai.com/v1/responses")!, headers: headers(), body: [
                "model": request.model, "stream": true, "instructions": AIRequest.systemPrompt,
                "input": input,
            ])
        }, decode: Self.decode)
    }

    private func headers() throws -> [String: String] {
        ["Authorization": "Bearer \(try HTTP.apiKey(credentials, for: id))"]
    }

    private static func decode(_ event: SSEEvent) throws -> HTTP.StreamEvent {
        let object = try HTTP.object(event)
        guard let type = object["type"] as? String else {
            throw ProviderError.malformedResponse("OpenAI event is missing its type.")
        }
        switch type {
        case "response.output_text.delta":
            guard let delta = object["delta"] as? String else {
                throw ProviderError.malformedResponse("OpenAI text event is missing its delta.")
            }
            return .text([delta])
        case "response.completed": return .finished
        case "error", "response.failed", "response.incomplete":
            let response = object["response"] as? [String: Any]
            let error = (response?["error"] ?? object["error"]) as? [String: Any]
            throw ProviderError.malformedResponse(error?["message"] as? String ?? object["message"] as? String ?? "OpenAI response did not complete.")
        default: return .text([])
        }
    }

    private struct ModelList: Decodable {
        let data: [Model]
        struct Model: Decodable {
            let id: String
            let created: Int?
        }
    }

    private static let fallbackModels = [
        AIModel(id: "gpt-5.5", displayName: "GPT-5.5"),
        AIModel(id: "gpt-5.4", displayName: "GPT-5.4"),
    ]
}
