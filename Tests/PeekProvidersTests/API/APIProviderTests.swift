import Foundation
import Testing
import PeekCore
@testable import PeekProviders

private let hostedIDs: [ProviderID] = [.anthropicAPI, .openAIAPI, .geminiAPI]

struct APIProviderTests {
    @Test func factoryMetadataAndAvailability() async throws {
        let credentials = InMemoryCredentialStore()
        let providers = apiProviders(credentials: credentials)
        #expect(providers.map(\.id) == hostedIDs)
        #expect(providers.map(\.displayName) == ["Anthropic API", "OpenAI API", "Gemini API"])
        for provider in providers {
            #expect(provider.supportsImages)
            #expect(await provider.availability() == .needsAPIKey)
            try credentials.setAPIKey("", for: provider.id)
            #expect(await provider.availability() == .needsAPIKey)
            try credentials.setAPIKey("test-key", for: provider.id)
            #expect(await provider.availability() == .ready)
        }
    }

    @Test(arguments: hostedIDs, [false, true])
    func requestAndStreaming(id: ProviderID, image: Bool) async throws {
        let stub = APIStub(body: fixture(id))
        let session = stub.session()
        defer { session.invalidateAndCancel(); stub.remove() }
        let credentials = InMemoryCredentialStore()
        try credentials.setAPIKey("test-key", for: id)
        let provider = apiProvider(id, credentials: credentials, session: session)
        let png = Data([137, 80, 78, 71, 0, 1, 2])
        let capture = Capture(content: .image(png), anchor: nil, sourceBundleID: nil)
        let request = AIRequest(messages: [AIMessage(role: .user, text: "Explain this", captures: image ? [capture] : [])], model: "test-model")
        var deltas: [String] = []
        for try await delta in provider.stream(request) { deltas.append(delta) }
        #expect(deltas == ["Hello", " 世界", "!"])
        let sent = try #require(stub.requests.first)
        #expect(stub.requests.count == 1)
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(sent.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        let object = try requestObject(sent)
        let blocks: [[String: Any]]
        switch id {
        case .anthropicAPI:
            #expect(sent.url?.absoluteString == "https://api.anthropic.com/v1/messages")
            #expect(sent.value(forHTTPHeaderField: "x-api-key") == "test-key")
            #expect(sent.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            #expect(object["model"] as? String == request.model)
            #expect(object["max_tokens"] as? Int == 8192)
            #expect(object["stream"] as? Bool == true)
            #expect(object["system"] as? String == AIRequest.systemPrompt)
            #expect(object["thinking"] == nil)
            #expect(object["temperature"] == nil)
            let messages = try #require(object["messages"] as? [[String: Any]])
            #expect(messages.count == 1)
            #expect(messages.first?["role"] as? String == "user")
            blocks = try #require(messages.first?["content"] as? [[String: Any]])
            #expect(blocks.last?["type"] as? String == "text")
            if image {
                #expect(blocks.first?["type"] as? String == "image")
                let source = try #require(blocks.first?["source"] as? [String: String])
                #expect(source == ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()])
            }
        case .openAIAPI:
            #expect(sent.url?.absoluteString == "https://api.openai.com/v1/responses")
            #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            #expect(object["model"] as? String == request.model)
            #expect(object["stream"] as? Bool == true)
            #expect(object["instructions"] as? String == AIRequest.systemPrompt)
            let input = try #require(object["input"] as? [[String: Any]])
            #expect(input.count == 1)
            #expect(input.first?["role"] as? String == "user")
            blocks = try #require(input.first?["content"] as? [[String: Any]])
            #expect(blocks.last?["type"] as? String == "input_text")
            if image {
                #expect(blocks.first?["type"] as? String == "input_image")
                #expect(blocks.first?["image_url"] as? String == "data:image/png;base64,\(png.base64EncodedString())")
            }
        case .geminiAPI:
            #expect(sent.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/test-model:streamGenerateContent?alt=sse")
            #expect(sent.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
            let system = try #require(object["system_instruction"] as? [String: Any])
            #expect(system["parts"] as? [[String: String]] == [["text": AIRequest.systemPrompt]])
            let contents = try #require(object["contents"] as? [[String: Any]])
            #expect(contents.count == 1)
            #expect(contents.first?["role"] as? String == "user")
            blocks = try #require(contents.first?["parts"] as? [[String: Any]])
            if image {
                #expect(blocks.first?["inline_data"] as? [String: String] == ["mime_type": "image/png", "data": png.base64EncodedString()])
            }
        default: return
        }
        #expect(blocks.count == (image ? 2 : 1))
        #expect(blocks.last?["text"] as? String == request.messages[0].text)
    }

    @Test(arguments: hostedIDs)
    func conversationPreservesRolesTextAndScreenshotTurns(id: ProviderID) async throws {
        let stub = APIStub(body: fixture(id))
        let session = stub.session()
        defer { session.invalidateAndCancel(); stub.remove() }
        let credentials = InMemoryCredentialStore()
        try credentials.setAPIKey("test-key", for: id)
        let provider = apiProvider(id, credentials: credentials, session: session)
        let conversation = ConversationFixture()
        for try await _ in provider.stream(conversation.request) {}
        let sent = try #require(stub.requests.first)
        let object = try requestObject(sent)
        let key = id == .anthropicAPI ? "messages" : id == .openAIAPI ? "input" : "contents"
        let messages = try #require(object[key] as? [[String: Any]])
        let assistantRole = id == .geminiAPI ? "model" : "assistant"
        #expect(messages.compactMap { $0["role"] as? String } == ["user", assistantRole, "user", assistantRole, "user"])
        let expectedImages = [[conversation.images[0]], [], [], [], [conversation.images[1], conversation.images[2]]]
        try #require(messages.count == expectedImages.count)
        for (index, message) in messages.enumerated() {
            let blocks = try #require(message[id == .geminiAPI ? "parts" : "content"] as? [[String: Any]])
            #expect(blocks.count == expectedImages[index].count + 1)
            #expect(blocks.last?["text"] as? String == conversation.texts[index])
            if id != .geminiAPI {
                #expect(blocks.last?["type"] as? String == (id == .openAIAPI ? "input_text" : "text"))
            }
            for (imageIndex, png) in expectedImages[index].enumerated() {
                let block = blocks[imageIndex]
                switch id {
                case .anthropicAPI:
                    #expect(block["type"] as? String == "image")
                    #expect(block["source"] as? [String: String] == ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()])
                case .openAIAPI:
                    #expect(block["type"] as? String == "input_image")
                    #expect(block["image_url"] as? String == "data:image/png;base64,\(png.base64EncodedString())")
                case .geminiAPI:
                    #expect(block["inline_data"] as? [String: String] == ["mime_type": "image/png", "data": png.base64EncodedString()])
                default: break
                }
            }
        }
        #expect(object["previous_response_id"] == nil)
        #expect(object["conversation"] == nil)
    }

    @Test(arguments: hostedIDs)
    func screenshotWithoutTextOmitsEmptyTextBlock(id: ProviderID) async throws {
        let stub = APIStub(body: fixture(id))
        let session = stub.session()
        defer { session.invalidateAndCancel(); stub.remove() }
        let credentials = InMemoryCredentialStore()
        try credentials.setAPIKey("test-key", for: id)
        let provider = apiProvider(id, credentials: credentials, session: session)
        let capture = Capture(content: .image(Data([1])), anchor: nil, sourceBundleID: nil)
        for try await _ in provider.stream(AIRequest(messages: [AIMessage(role: .user, text: "", captures: [capture])], model: "test")) {}
        let object = try requestObject(#require(stub.requests.first))
        let key = id == .anthropicAPI ? "messages" : id == .openAIAPI ? "input" : "contents"
        let messages = try #require(object[key] as? [[String: Any]])
        let blocks = try #require(messages.first?[id == .geminiAPI ? "parts" : "content"] as? [[String: Any]])
        #expect(blocks.count == 1)
        #expect(blocks.first?["text"] == nil)
    }

    @Test(arguments: hostedIDs)
    func mapsHTTPError(id: ProviderID) async throws {
        let body = "{\"error\":\"rate limited\"}\nTry later.\n"
        let stub = APIStub(status: 429, body: body)
        let session = stub.session()
        defer { session.invalidateAndCancel(); stub.remove() }
        let credentials = InMemoryCredentialStore()
        try credentials.setAPIKey("test-key", for: id)
        let provider = apiProvider(id, credentials: credentials, session: session)
        await #expect(throws: ProviderError.http(status: 429, body: body)) {
            for try await _ in provider.stream(AIRequest(messages: [AIMessage(role: .user, text: "test")], model: "model")) {}
        }
    }

    @Test(arguments: hostedIDs)
    func missingKeyDoesNotStartRequest(id: ProviderID) async throws {
        let stub = APIStub(body: "")
        let session = stub.session()
        defer { session.invalidateAndCancel(); stub.remove() }
        let provider = apiProvider(id, credentials: InMemoryCredentialStore(), session: session)
        await #expect(throws: ProviderError.notAvailable(.needsAPIKey)) {
            for try await _ in provider.stream(AIRequest(messages: [AIMessage(role: .user, text: "test")], model: "model")) {}
        }
        #expect(stub.requests.isEmpty)
    }

    @Test(arguments: hostedIDs)
    func malformedJSONThrows(id: ProviderID) async throws {
        try await expectMalformed(id, body: "data: not json\n\n")
        try await expectMalformed(id, body: "data: {}\n\n")
    }

    @Test func providerErrorEventsThrow() async throws {
        try await expectMalformed(.anthropicAPI, body: "event: error\ndata: {\"type\":\"error\",\"error\":{\"message\":\"Overloaded\"}}\n\n", message: "Overloaded")
        try await expectMalformed(.openAIAPI, body: "data: {\"type\":\"error\",\"message\":\"Bad request\"}\n\n", message: "Bad request")
        try await expectMalformed(.openAIAPI, body: "data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"message\":\"Failed\"}}}\n\n", message: "Failed")
        try await expectMalformed(.geminiAPI, body: "data: {\"error\":{\"message\":\"Quota exceeded\"}}\n\n", message: "Quota exceeded")
        try await expectMalformed(.anthropicAPI, body: "event: error\ndata: {\"error\":{\"message\":\"Overloaded\"}}\n\n", message: "Overloaded")
        try await expectMalformed(.openAIAPI, body: "data: {\"type\":\"response.incomplete\"}\n\n")
        try await expectMalformed(.geminiAPI, body: "data: {\"promptFeedback\":{\"blockReason\":\"SAFETY\"}}\n\n")
    }

    @Test func invalidTextDeltasThrow() async throws {
        try await expectMalformed(.anthropicAPI, body: "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\"}}\n\n")
        try await expectMalformed(.openAIAPI, body: "data: {\"type\":\"response.output_text.delta\",\"delta\":42}\n\n")
        try await expectMalformed(.geminiAPI, body: "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":42}]}}]}\n\n")
    }

    @Test(arguments: [ProviderID.anthropicAPI, .openAIAPI])
    func truncatedStreamThrows(id: ProviderID) async throws {
        let body = id == .anthropicAPI
            ? "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"partial\"}}\n\n"
            : "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n"
        try await expectMalformed(id, body: body)
    }

    @Test(arguments: [ProviderID.anthropicAPI, .openAIAPI])
    func completionEventStopsOpenRequest(id: ProviderID) async throws {
        let stub = APIStub(body: fixture(id), holdsOpen: true)
        let session = stub.session()
        defer { session.invalidateAndCancel(); stub.remove() }
        let credentials = InMemoryCredentialStore()
        try credentials.setAPIKey("test-key", for: id)
        let provider = apiProvider(id, credentials: credentials, session: session)
        let task = Task {
            var text = ""
            for try await delta in provider.stream(AIRequest(messages: [AIMessage(role: .user, text: "test")], model: "model")) { text += delta }
            return text
        }
        defer { task.cancel() }
        try await waitForStub { stub.stops > 0 }
        guard stub.stops > 0 else { return }
        #expect(try await task.value == "Hello 世界!")
    }

    @Test(arguments: hostedIDs)
    func cancellationStopsRequest(id: ProviderID) async throws {
        let stub = APIStub(body: ": waiting\n\n", holdsOpen: true)
        let session = stub.session()
        defer { session.invalidateAndCancel(); stub.remove() }
        let credentials = InMemoryCredentialStore()
        try credentials.setAPIKey("test-key", for: id)
        let provider = apiProvider(id, credentials: credentials, session: session)
        let task = Task {
            do {
                for try await _ in provider.stream(AIRequest(messages: [AIMessage(role: .user, text: "test")], model: "model")) {}
            } catch {}
        }
        try await waitForStub { !stub.requests.isEmpty }
        task.cancel()
        await task.value
        try await waitForStub { stub.stops > 0 }
    }

    private func expectMalformed(_ id: ProviderID, body: String, message: String? = nil) async throws {
        let stub = APIStub(body: body)
        let session = stub.session()
        defer { session.invalidateAndCancel(); stub.remove() }
        let credentials = InMemoryCredentialStore()
        try credentials.setAPIKey("test-key", for: id)
        let provider = apiProvider(id, credentials: credentials, session: session)
        do {
            for try await _ in provider.stream(AIRequest(messages: [AIMessage(role: .user, text: "test")], model: "model")) {}
            Issue.record("Expected a malformed response error.")
        } catch let error as ProviderError {
            guard case .malformedResponse(let detail) = error else {
                Issue.record("Unexpected provider error: \(error)")
                return
            }
            if let message { #expect(detail == message) }
        }
    }

    private func fixture(_ id: ProviderID) -> String {
        switch id {
        case .anthropicAPI:
            return """
            : keepalive

            event: message_start
            data: {"type":"message_start","message":{}}

            event: content_block_delta
            data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}

            event: content_block_delta
            data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"private"}}

            event: content_block_delta
            data: {"type":"content_block_delta",
            data: "delta":{"type":"text_delta","text":" 世界"}}

            event: content_block_delta
            data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"!"}}

            event: message_stop
            data: {"type":"message_stop"}

            data: invalid after stop

            """ + "\n"
        case .openAIAPI:
            return """
            event: response.created
            data: {"type":"response.created"}

            event: response.output_text.delta
            data: {"type":"response.output_text.delta","delta":"Hello"}

            data: {"type":"response.output_text.delta","delta":" 世界"}

            data: {"type":"response.output_text.delta","delta":"!"}

            data: {"type":"response.completed"}

            data: invalid after completion

            """ + "\n"
        case .geminiAPI:
            return """
            : keepalive

            data: {"candidates":[{"content":{"parts":[{"text":"private","thought":true},{"text":"Hello"},{"text":" 世界"}]}}]}

            data: {"candidates":[{"content":{"parts":[{"text":"!"}]},"finishReason":"STOP"}]}

            data: {"usageMetadata":{"totalTokenCount":12}}

            """ + "\n"
        default: return ""
        }
    }
}
