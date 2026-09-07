import Foundation
import Testing
@testable import PeekCore

@Test func settingsRoundTrip() {
    let defaults = UserDefaults(suiteName: "PeekCoreTests.\(UUID().uuidString)")!
    let store = UserDefaultsSettingsStore(defaults: defaults)
    var s = AppSettings()
    s.provider = .codexCLI
    s.model = "gpt-5.6-sol"
    store.save(s)
    #expect(store.load() == s)
}

@Test func inMemoryCredentials() throws {
    let store = InMemoryCredentialStore()
    try store.setAPIKey("k", for: .geminiAPI)
    #expect(store.apiKey(for: .geminiAPI) == "k")
    try store.setAPIKey(nil, for: .geminiAPI)
    #expect(store.apiKey(for: .geminiAPI) == nil)
}
