import Foundation
import PeekCore
import Testing
@testable import PeekUI

@Test @MainActor func settingsPersistThroughUserDefaultsStore() async throws {
    let suite = "PeekUISettings.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsSettingsStore(defaults: defaults)
    let credentials = InMemoryCredentialStore()
    let model = SettingsModel(providers: [TestProvider()], store: store, credentials: credentials)
    #expect(model.addMode(name: "Summarize", prompt: "Summarize this\nUse short sentences."))
    model.settings.claudePath = "/custom/claude"
    model.settings.codexPath = "/custom/codex"
    model.settings.provider = .openAIAPI
    model.settings.model = "chosen-model"
    let restored = SettingsModel(providers: [TestProvider()], store: store, credentials: credentials)
    #expect(restored.settings == model.settings)
    #expect(restored.settings.selectedMode?.name == "Summarize")
    #expect(restored.settings.selectedMode?.prompt == "Summarize this\nUse short sentences.")
    model.saveKey("unit-test-key", for: .openAIAPI)
    #expect(credentials.apiKey(for: .openAIAPI) == "unit-test-key")
    let persisted = try #require(defaults.data(forKey: "appSettings"))
    #expect(!String(decoding: persisted, as: UTF8.self).contains("unit-test-key"))
    model.saveKey("", for: .openAIAPI)
    #expect(credentials.apiKey(for: .openAIAPI) == nil)
}

@Test @MainActor func modeEditsPersistAndKeepSelectionConsistent() throws {
    let suite = "PeekUISettings.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsSettingsStore(defaults: defaults)
    let model = SettingsModel(providers: [], store: store, credentials: InMemoryCredentialStore())
    let original = try #require(model.settings.selectedMode)

    #expect(model.addMode(name: " Translate ", prompt: " Translate into French.\nKeep formatting. "))
    let added = try #require(model.settings.selectedMode)
    #expect(added.id != original.id)
    #expect(added.name == "Translate")
    #expect(added.prompt == "Translate into French.\nKeep formatting.")
    #expect(store.load() == model.settings)

    let edited = PromptMode(id: added.id, name: "Translate to Spanish", prompt: "Translate into Spanish.")
    #expect(model.updateMode(edited))
    #expect(model.settings.selectedMode == edited)
    #expect(store.load().selectedMode == edited)

    #expect(model.deleteMode(id: added.id))
    #expect(model.settings.selectedMode == original)
    #expect(model.settings.modes == [original])
    #expect(store.load() == model.settings)
    #expect(!model.canDeleteMode(id: original.id))
    #expect(!model.deleteMode(id: original.id))
    #expect(model.settings.selectedMode == original)
}

@Test @MainActor func invalidModeEditsLeaveSettingsUnchanged() throws {
    let suite = "PeekUISettings.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsSettingsStore(defaults: defaults)
    let model = SettingsModel(providers: [], store: store, credentials: InMemoryCredentialStore())
    let original = model.settings
    let selected = try #require(original.selectedMode)

    #expect(!model.addMode(name: " \n", prompt: "Explain"))
    #expect(!model.addMode(name: "Explain", prompt: " \n"))
    #expect(!model.updateMode(PromptMode(id: selected.id, name: "", prompt: "Explain")))
    #expect(!model.updateMode(PromptMode(id: selected.id, name: "Explain", prompt: " \n")))
    #expect(!model.updateMode(PromptMode(name: "Unknown", prompt: "Explain")))
    #expect(!model.deleteMode(id: UUID()))
    #expect(model.settings == original)
}

@Test @MainActor func deletingUnselectedModePreservesActiveMode() throws {
    let suite = "PeekUISettings.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsSettingsStore(defaults: defaults)
    let model = SettingsModel(providers: [], store: store, credentials: InMemoryCredentialStore())
    let original = try #require(model.settings.selectedMode)
    #expect(model.addMode(name: "Summarize", prompt: "Summarize this"))
    let selected = model.settings.selectedMode
    #expect(model.deleteMode(id: original.id))
    #expect(model.settings.selectedMode == selected)
    #expect(store.load() == model.settings)
}

@Test @MainActor func deletingSelectedModeSkipsUnusableModes() throws {
    let suite = "PeekUISettings.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsSettingsStore(defaults: defaults)
    let active = PromptMode(name: "Explain", prompt: "Explain this")
    let invalid = PromptMode(name: "Blank", prompt: " \n")
    let replacement = PromptMode(name: "Summarize", prompt: "Summarize this")
    store.save(AppSettings(modes: [active, invalid, replacement], selectedModeID: active.id))
    let model = SettingsModel(providers: [], store: store, credentials: InMemoryCredentialStore())
    #expect(model.deleteMode(id: active.id))
    #expect(model.settings.selectedMode == replacement)
    #expect(!model.deleteMode(id: replacement.id))
    #expect(store.load() == model.settings)
}

@Test @MainActor func selectedProviderModelsAndAvailabilityLoad() async {
    let suite = "PeekUISettings.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsSettingsStore(defaults: defaults)
    let model = SettingsModel(providers: [TestProvider()], store: store, credentials: InMemoryCredentialStore())
    await model.refreshAvailability()
    await model.loadModels()
    #expect(model.availability[.anthropicAPI] == .ready)
    #expect(model.models.map(\.id) == ["test-model"])
    #expect(store.load().model == "test-model")
    #expect(!model.isLoadingModels)
}

@Test func modeShortcutNameFollowsModeID() {
    let id = UUID(uuidString: "496B13F2-3390-4B08-93DC-24E47562845F")!
    let mode = PromptMode(id: id, name: "Explain", prompt: "Explain this")
    let renamed = PromptMode(id: id, name: "Summarize", prompt: "Summarize this")
    #expect(mode.shortcutName == renamed.shortcutName)
    #expect(mode.shortcutName.rawValue == "mode.496B13F2-3390-4B08-93DC-24E47562845F")
    #expect(mode.shortcutName.defaultShortcut == nil)
    #expect(mode.shortcutName != PromptMode(name: "Explain", prompt: "Explain this").shortcutName)
}

@Test @MainActor func settingsChangesNotifyObserver() throws {
    let suite = "PeekUISettings.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsSettingsStore(defaults: defaults)
    let model = SettingsModel(providers: [], store: store, credentials: InMemoryCredentialStore())
    var seen: [[UUID]] = []
    model.onChange = { seen.append(store.load().modes.map(\.id)) }
    #expect(model.addMode(name: "Summarize", prompt: "Summarize this"))
    let added = try #require(model.settings.selectedMode)
    #expect(model.deleteMode(id: added.id))
    #expect(seen == [model.settings.modes.map(\.id) + [added.id], model.settings.modes.map(\.id)])
}
