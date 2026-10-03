import Foundation

public struct PromptMode: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var prompt: String
    /// Holds screenshots in the composer until the user adds context and sends.
    public var waitsForContext: Bool

    public init(id: UUID = UUID(), name: String, prompt: String, waitsForContext: Bool = false) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.waitsForContext = waitsForContext
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        prompt = try container.decode(String.self, forKey: .prompt)
        // Modes saved before this flag existed load with it off instead of resetting all settings.
        waitsForContext = try container.decodeIfPresent(Bool.self, forKey: .waitsForContext) ?? false
    }
}

/// User preferences persisted in UserDefaults. Secrets live in CredentialStore, never here.
public struct AppSettings: Sendable, Equatable, Codable {
    public var provider: ProviderID
    public var model: String
    public var modes: [PromptMode]
    public var selectedModeID: UUID?
    public var selectedMode: PromptMode? { modes.first { $0.id == selectedModeID } }
    /// Path override for the `claude` binary; nil means search PATH and common install locations.
    public var claudePath: String?
    /// Path override for the `codex` binary; nil means search PATH and common install locations.
    public var codexPath: String?
    /// Run Claude Code without CLAUDE.md and other user customizations.
    public var claudeIgnoresInstructions: Bool

    public init(provider: ProviderID = .anthropicAPI, model: String = "claude-opus-5", modes: [PromptMode]? = nil, selectedModeID: UUID? = nil, claudePath: String? = nil, codexPath: String? = nil, claudeIgnoresInstructions: Bool = true) {
        self.provider = provider
        self.model = model
        if let modes {
            self.modes = modes
            self.selectedModeID = selectedModeID
        } else {
            let initialMode = PromptMode(id: UUID(uuidString: "496B13F2-3390-4B08-93DC-24E47562845F")!,
                                         name: "Explain", prompt: "Explain this")
            self.modes = [initialMode]
            self.selectedModeID = initialMode.id
        }
        self.claudePath = claudePath
        self.codexPath = codexPath
        self.claudeIgnoresInstructions = claudeIgnoresInstructions
    }
}

public protocol SettingsStore: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

public struct UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "appSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: key)
    }
}
