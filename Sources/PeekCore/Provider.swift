import Foundation

public enum ProviderID: String, Sendable, CaseIterable, Codable, Identifiable {
    case anthropicAPI
    case openAIAPI
    case geminiAPI
    case claudeCLI
    case codexCLI

    public var id: String { rawValue }
}

public struct AIModel: Sendable, Identifiable, Equatable, Codable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public enum ProviderAvailability: Sendable, Equatable {
    case ready
    case needsAPIKey
    case cliNotInstalled
    case cliNotLoggedIn
    case unavailable(String)
}

public struct AIRequest: Sendable {
    public let question: String
    public let capture: Capture?
    public let model: String

    public init(question: String, capture: Capture?, model: String) {
        self.question = question
        self.capture = capture
        self.model = model
    }
}

public enum ProviderError: Error, Sendable, Equatable {
    case notAvailable(ProviderAvailability)
    case imagesNotSupported
    case http(status: Int, body: String)
    case malformedResponse(String)
    case processFailed(exitCode: Int32, stderr: String)
    case cancelled
}

/// One way of getting an answer: a hosted API keyed by the user, or a locally installed CLI using its own login.
public protocol AIProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    var supportsImages: Bool { get }

    func availability() async -> ProviderAvailability
    func models() async throws -> [AIModel]
    /// Streams answer text deltas. Finishes when the answer is complete; throws ProviderError on failure.
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error>
}
