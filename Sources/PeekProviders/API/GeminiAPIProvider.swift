import Foundation
import PeekCore

public struct GeminiAPIProvider: AIProvider {
    public let id = ProviderID.geminiAPI
    public let displayName = "Gemini API"
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
            let request = try HTTP.request(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!, headers: headers())
            let data = try await HTTP.data(for: request, session: session)
            let response = try JSONDecoder().decode(ModelList.self, from: data)
            let models = response.models.filter { $0.supportedGenerationMethods.contains("generateContent") }.map {
                AIModel(id: $0.name.hasPrefix("models/") ? String($0.name.dropFirst(7)) : $0.name, displayName: $0.displayName)
            }.sorted { $0.id.compare($1.id, options: .numeric) == .orderedDescending }
            return models.isEmpty ? Self.fallbackModels : models
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw ProviderError.cancelled
            }
            return Self.fallbackModels
        }
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        HTTP.stream(session: session, endsOnEOF: true, request: {
            let contents: [[String: Any]] = request.messages.map { message in
                var parts: [[String: Any]] = message.captures.map { capture in
                    let png = switch capture.content { case .image(let data): data }
                    return ["inline_data": ["mime_type": "image/png", "data": png.base64EncodedString()]]
                }
                if !message.text.isEmpty { parts.append(["text": message.text]) }
                return ["role": message.role == .assistant ? "model" : "user", "parts": parts]
            }
            var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
            components.path += "/\(request.model):streamGenerateContent"
            components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
            guard let url = components.url else { throw ProviderError.malformedResponse("Invalid Gemini model URL.") }
            return try HTTP.request(url: url, headers: headers(), body: [
                "system_instruction": ["parts": [["text": AIRequest.systemPrompt]]],
                "contents": contents,
            ])
        }, decode: Self.decode)
    }

    private func headers() throws -> [String: String] {
        ["x-goog-api-key": try HTTP.apiKey(credentials, for: id)]
    }

    private static func decode(_ event: SSEEvent) throws -> HTTP.StreamEvent {
        let object = try HTTP.object(event)
        if let error = object["error"] as? [String: Any] {
            throw ProviderError.malformedResponse(error["message"] as? String ?? "Gemini stream failed.")
        }
        if let feedback = object["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
            throw ProviderError.malformedResponse("Gemini blocked the prompt: \(reason).")
        }
        guard let candidates = object["candidates"] as? [[String: Any]] else {
            if object["usageMetadata"] is [String: Any] { return .text([]) }
            throw ProviderError.malformedResponse("Gemini event is missing its candidates.")
        }
        guard let candidate = candidates.first else { return .text([]) }
        if let reason = candidate["finishReason"] as? String, reason != "STOP", reason != "MAX_TOKENS" {
            throw ProviderError.malformedResponse("Gemini stopped generation: \(reason).")
        }
        guard let content = candidate["content"] as? [String: Any] else {
            if candidate["finishReason"] is String { return .text([]) }
            throw ProviderError.malformedResponse("Gemini candidate is missing its content.")
        }
        guard let parts = content["parts"] as? [[String: Any]] else {
            throw ProviderError.malformedResponse("Gemini content is missing its parts.")
        }
        var deltas: [String] = []
        for part in parts {
            if part["thought"] as? Bool == true { continue }
            if let text = part["text"] as? String { deltas.append(text) }
            else if part["text"] != nil { throw ProviderError.malformedResponse("Gemini text part is invalid.") }
        }
        return .text(deltas)
    }

    private struct ModelList: Decodable {
        let models: [Model]
        struct Model: Decodable {
            let name: String
            let displayName: String
            let supportedGenerationMethods: [String]
        }
    }

    private static let fallbackModels = [
        AIModel(id: "gemini-3.1-pro-preview", displayName: "Gemini 3.1 Pro"),
        AIModel(id: "gemini-3.5-flash", displayName: "Gemini 3.5 Flash"),
    ]
}
