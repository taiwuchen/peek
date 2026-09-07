import Foundation

/// User preferences persisted in UserDefaults. Secrets live in CredentialStore, never here.
public struct AppSettings: Sendable, Equatable, Codable {
    public var provider: ProviderID
    public var model: String
    /// Path override for the `claude` binary; nil means search PATH and common install locations.
    public var claudePath: String?
    /// Path override for the `codex` binary; nil means search PATH and common install locations.
    public var codexPath: String?

    public init(provider: ProviderID = .anthropicAPI, model: String = "claude-opus-5", claudePath: String? = nil, codexPath: String? = nil) {
        self.provider = provider
        self.model = model
        self.claudePath = claudePath
        self.codexPath = codexPath
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
