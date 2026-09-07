import Foundation
import PeekCore

enum HTTP {
    enum StreamEvent: Sendable {
        case text([String])
        case finished
    }

    static func apiKey(_ credentials: any CredentialStore, for provider: ProviderID) throws -> String {
        guard let key = credentials.apiKey(for: provider), !key.isEmpty else {
            throw ProviderError.notAvailable(.needsAPIKey)
        }
        return key
    }

    static func request(url: URL, headers: [String: String], body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    static func data(for request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try validate(response, body: data)
        return data
    }

    static func object(_ event: SSEEvent) throws -> [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: Data(event.data.utf8)),
              let object = value as? [String: Any] else {
            throw ProviderError.malformedResponse("Invalid JSON in SSE event \(event.event).")
        }
        return object
    }

    static func stream(
        session: URLSession,
        endsOnEOF: Bool = false,
        request: @escaping @Sendable () throws -> URLRequest,
        decode: @escaping @Sendable (SSEEvent) throws -> StreamEvent
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    let (bytes, response) = try await session.bytes(for: request())
                    defer { bytes.task.cancel() }
                    try await withTaskCancellationHandler {
                        guard let response = response as? HTTPURLResponse else {
                            throw ProviderError.malformedResponse("Expected an HTTP response.")
                        }
                        if !(200..<300).contains(response.statusCode) {
                            var body = Data()
                            for try await byte in bytes { body.append(byte) }
                            throw ProviderError.http(status: response.statusCode, body: String(decoding: body, as: UTF8.self))
                        }
                        var parser = SSEParser()
                        var receivedEvent = false
                        for try await line in SSELineSequence(bytes: bytes) {
                            try Task.checkCancellation()
                            guard let event = parser.consume(line) else { continue }
                            receivedEvent = true
                            switch try decode(event) {
                            case .text(let deltas):
                                for delta in deltas { continuation.yield(delta) }
                            case .finished: return
                            }
                        }
                        if !endsOnEOF || !receivedEvent {
                            throw ProviderError.malformedResponse("The response stream ended before completion.")
                        }
                    } onCancel: {
                        bytes.task.cancel()
                    }
                    continuation.finish()
                } catch {
                    let cancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError
                    continuation.finish(throwing: cancelled ? ProviderError.cancelled : error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func validate(_ response: URLResponse, body: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw ProviderError.malformedResponse("Expected an HTTP response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderError.http(status: response.statusCode, body: String(decoding: body, as: UTF8.self))
        }
    }
}
