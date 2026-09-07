import Foundation
import Security

public protocol CredentialStore: Sendable {
    func apiKey(for provider: ProviderID) -> String?
    func setAPIKey(_ key: String?, for provider: ProviderID) throws
}

/// Stores API keys in the login keychain under one service name, account = provider id.
public struct KeychainCredentialStore: CredentialStore {
    private let service: String

    public init(service: String = "com.taiwu.peek.api-keys") {
        self.service = service
    }

    public func apiKey(for provider: ProviderID) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setAPIKey(_ key: String?, for provider: ProviderID) throws {
        let query = baseQuery(provider)
        SecItemDelete(query as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(key.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    private func baseQuery(_ provider: ProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }
}

public enum KeychainError: Error, Sendable {
    case status(OSStatus)
}

/// In-memory store for tests and previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var keys: [ProviderID: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func apiKey(for provider: ProviderID) -> String? {
        lock.withLock { keys[provider] }
    }

    public func setAPIKey(_ key: String?, for provider: ProviderID) throws {
        lock.withLock { keys[provider] = key }
    }
}
