import Foundation
import Testing
import PeekCore
@testable import PeekProviders

struct APIModelTests {
    @Test(arguments: [ProviderID.anthropicAPI, .openAIAPI, .geminiAPI])
    func listsModels(id: ProviderID) async throws {
        let fixture: String
        let expected: [AIModel]
        let url: String
        switch id {
        case .anthropicAPI:
            fixture = #"{"data":[{"id":"claude-haiku-4-5","display_name":"Claude Haiku 4.5","created_at":"2025-10-01"},{"id":"claude-sonnet-5","display_name":"Claude Sonnet 5","created_at":"2026-04-01"},{"id":"claude-opus-5","display_name":"Claude Opus 5","created_at":"2026-04-01"}]}"#
            expected = [AIModel(id: "claude-opus-5", displayName: "Claude Opus 5"), AIModel(id: "claude-sonnet-5", displayName: "Claude Sonnet 5"), AIModel(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5")]
            url = "https://api.anthropic.com/v1/models"
        case .openAIAPI:
            fixture = #"{"data":[{"id":"gpt-5.4","created":2},{"id":"gpt-5.5","created":3},{"id":"o3","created":1},{"id":"gpt-realtime"},{"id":"gpt-audio"},{"id":"gpt-tts"},{"id":"gpt-transcribe"},{"id":"gpt-image"},{"id":"gpt-embedding"},{"id":"omni-moderation"},{"id":"dall-e-3"}]}"#
            expected = [AIModel(id: "gpt-5.5", displayName: "GPT-5.5"), AIModel(id: "gpt-5.4", displayName: "GPT-5.4"), AIModel(id: "o3", displayName: "o3")]
            url = "https://api.openai.com/v1/models"
        case .geminiAPI:
            fixture = #"{"models":[{"name":"models/gemini-2.5-flash","displayName":"Gemini 2.5 Flash","supportedGenerationMethods":["generateContent"]},{"name":"models/gemini-3.1-pro-preview","displayName":"Gemini 3.1 Pro","supportedGenerationMethods":["generateContent","countTokens"]},{"name":"models/embedding-001","displayName":"Embedding","supportedGenerationMethods":["embedContent"]}]}"#
            expected = [AIModel(id: "gemini-3.1-pro-preview", displayName: "Gemini 3.1 Pro"), AIModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash")]
            url = "https://generativelanguage.googleapis.com/v1beta/models"
        default: return
        }
        let stub = APIStub(body: fixture)
        let session = stub.session()
        defer { session.invalidateAndCancel(); stub.remove() }
        let credentials = InMemoryCredentialStore()
        try credentials.setAPIKey("test-key", for: id)
        let provider = apiProvider(id, credentials: credentials, session: session)
        #expect(try await provider.models() == expected)
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == url)
        switch id {
        case .anthropicAPI:
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        case .openAIAPI:
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        case .geminiAPI:
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
        default: break
        }
    }

    @Test(arguments: [ProviderID.anthropicAPI, .openAIAPI, .geminiAPI])
    func fallsBackOnHTTPDecodingAndTransportFailures(id: ProviderID) async throws {
        let credentials = InMemoryCredentialStore()
        try credentials.setAPIKey("test-key", for: id)
        for stub in [APIStub(status: 500, body: "unavailable"), APIStub(body: "not JSON"), APIStub(body: "{}"), APIStub(body: "", transportError: .notConnectedToInternet)] {
            let session = stub.session()
            defer { session.invalidateAndCancel(); stub.remove() }
            let provider = apiProvider(id, credentials: credentials, session: session)
            #expect(try await provider.models().map(\.id) == fallbackIDs(id))
        }
    }

    @Test(arguments: [ProviderID.anthropicAPI, .openAIAPI, .geminiAPI])
    func missingKeyReturnsFallbackWithoutNetwork(id: ProviderID) async throws {
        let stub = APIStub(body: "")
        let session = stub.session()
        defer { session.invalidateAndCancel(); stub.remove() }
        let provider = apiProvider(id, credentials: InMemoryCredentialStore(), session: session)
        #expect(try await provider.models().map(\.id) == fallbackIDs(id))
        #expect(stub.requests.isEmpty)
    }

    private func fallbackIDs(_ id: ProviderID) -> [String] {
        switch id {
        case .anthropicAPI: ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"]
        case .openAIAPI: ["gpt-5.5", "gpt-5.4"]
        case .geminiAPI: ["gemini-3.1-pro-preview", "gemini-3.5-flash"]
        default: []
        }
    }
}
