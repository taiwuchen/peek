import Foundation
import Synchronization
import Testing
import PeekCore
@testable import PeekProviders

final class APIStub: Sendable {
    let id = UUID().uuidString
    let status: Int
    let body: String
    let holdsOpen: Bool
    let transportError: URLError.Code?
    private let state = Mutex((requests: [URLRequest](), stops: 0))

    init(status: Int = 200, body: String, holdsOpen: Bool = false, transportError: URLError.Code? = nil) {
        self.status = status
        self.body = body
        self.holdsOpen = holdsOpen
        self.transportError = transportError
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }
    var stops: Int { state.withLock { $0.stops } }
    func record(_ request: URLRequest) { state.withLock { $0.requests.append(request) } }
    func stop() { state.withLock { $0.stops += 1 } }

    func session() -> URLSession {
        APIStubProtocol.stubs.withLock { $0[id] = self }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIStubProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Peek-Test-ID": id]
        return URLSession(configuration: configuration)
    }

    func remove() { _ = APIStubProtocol.stubs.withLock { $0.removeValue(forKey: id) } }
}

final class APIStubProtocol: URLProtocol, @unchecked Sendable {
    static let stubs = Mutex<[String: APIStub]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var stub: APIStub? {
        guard let id = request.value(forHTTPHeaderField: "X-Peek-Test-ID") else { return nil }
        return Self.stubs.withLock { $0[id] }
    }

    override func startLoading() {
        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        stub.record(request)
        if let error = stub.transportError {
            client?.urlProtocol(self, didFailWithError: URLError(error))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let data = Data(stub.body.utf8)
        for offset in stride(from: 0, to: data.count, by: 7) {
            client?.urlProtocol(self, didLoad: data.subdata(in: offset..<min(offset + 7, data.count)))
        }
        if !stub.holdsOpen { client?.urlProtocolDidFinishLoading(self) }
    }

    override func stopLoading() { stub?.stop() }
}

func apiProvider(_ id: ProviderID, credentials: any CredentialStore, session: URLSession) -> any AIProvider {
    switch id {
    case .anthropicAPI: AnthropicAPIProvider(credentials: credentials, session: session)
    case .openAIAPI: OpenAIAPIProvider(credentials: credentials, session: session)
    case .geminiAPI: GeminiAPIProvider(credentials: credentials, session: session)
    default: preconditionFailure("Expected a hosted API provider.")
    }
}

func requestObject(_ request: URLRequest) throws -> [String: Any] {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

func waitForStub(_ condition: @Sendable () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    #expect(condition())
}
