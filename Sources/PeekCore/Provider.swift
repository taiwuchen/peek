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

public struct AIMessage: Sendable, Equatable, Identifiable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public var text: String
    public let captures: [Capture]

    public init(id: UUID = UUID(), role: Role, text: String, captures: [Capture] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.captures = captures
    }
}

public struct AIRequest: Sendable {
    public let messages: [AIMessage]
    public let model: String

    public init(messages: [AIMessage], model: String) {
        self.messages = messages
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

extension AIRequest {
    /// System instruction shared by every provider.
    public static let systemPrompt = "You are a concise assistant embedded in the user's macOS desktop. The user captures screen regions as screenshots and asks questions about them. Use the conversation history to answer follow-up questions, keeping each screenshot associated with the turn where it was shared. Answer the latest user message directly in plain Markdown. Do not restate the content."
}
