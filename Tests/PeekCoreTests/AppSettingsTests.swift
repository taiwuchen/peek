import Foundation
import Testing
@testable import PeekCore

@Test func settingsRoundTrip() {
    let suite = "PeekCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsSettingsStore(defaults: defaults)
    let explain = PromptMode(name: "Explain", prompt: "Explain this")
    let translate = PromptMode(name: "Translate", prompt: "Translate this into French.\nKeep the formatting.")
    var s = AppSettings(modes: [explain, translate], selectedModeID: translate.id)
    s.provider = .codexCLI
    s.model = "gpt-5.6-sol"
    store.save(s)
    #expect(store.load() == s)
    #expect(store.load().selectedMode == translate)
}

@Test func initialSettingsSelectExplainMode() throws {
    let settings = AppSettings()
    let mode = try #require(settings.selectedMode)
    #expect(settings.modes == [mode])
    #expect(mode.name == "Explain")
    #expect(mode.prompt == "Explain this")
}

@Test func unsetStoreLoadsUseStableDefaultModeIdentity() {
    let suite = "PeekCoreTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsSettingsStore(defaults: defaults)
    let firstLoad = store.load()
    let secondLoad = UserDefaultsSettingsStore(defaults: defaults).load()
    #expect(firstLoad == secondLoad)
    #expect(firstLoad.selectedModeID == AppSettings().selectedModeID)
    #expect(firstLoad.modes.contains { $0.id == secondLoad.selectedModeID })
}

@Test func explicitModesPreserveSelection() {
    let mode = PromptMode(name: "Summarize", prompt: "Summarize this")
    #expect(AppSettings(modes: [mode], selectedModeID: mode.id).selectedMode == mode)
    #expect(AppSettings(modes: [mode]).selectedMode == nil)
    #expect(AppSettings(modes: [mode], selectedModeID: UUID()).selectedMode == nil)
    #expect(AppSettings(modes: []).modes.isEmpty)
}

@Test func emptyModesAndNoSelectionPersist() {
    let suite = "PeekCoreTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsSettingsStore(defaults: defaults)
    let settings = AppSettings(modes: [])
    store.save(settings)
    #expect(store.load() == settings)
    #expect(store.load().selectedMode == nil)
}

@Test func inMemoryCredentials() throws {
    let store = InMemoryCredentialStore()
    try store.setAPIKey("k", for: .geminiAPI)
    #expect(store.apiKey(for: .geminiAPI) == "k")
    try store.setAPIKey(nil, for: .geminiAPI)
    #expect(store.apiKey(for: .geminiAPI) == nil)
}
