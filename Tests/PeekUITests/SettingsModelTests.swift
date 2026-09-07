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
    model.settings.defaultQuestion = "Summarize this"
    model.settings.claudePath = "/custom/claude"
    model.settings.codexPath = "/custom/codex"
    model.settings.provider = .openAIAPI
    model.settings.model = "chosen-model"
    let restored = SettingsModel(providers: [TestProvider()], store: store, credentials: credentials)
    #expect(restored.settings == model.settings)
    model.saveKey("unit-test-key", for: .openAIAPI)
    #expect(credentials.apiKey(for: .openAIAPI) == "unit-test-key")
    let persisted = try #require(defaults.data(forKey: "appSettings"))
    #expect(!String(decoding: persisted, as: UTF8.self).contains("unit-test-key"))
    model.saveKey("", for: .openAIAPI)
    #expect(credentials.apiKey(for: .openAIAPI) == nil)
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

@Test func markdownSeparatesParagraphsAndStreamingCodeBlocks() {
    #expect(MarkdownBlock.parse("A **paragraph**.\n\n```swift\nlet x = 1\n\nprint(x)") == [
        MarkdownBlock(text: "A **paragraph**.", isCode: false),
        MarkdownBlock(text: "let x = 1\n\nprint(x)", isCode: true),
    ])
    #expect(MarkdownBlock.parse("~~~\ncode\n~~~\n\nAfter") == [
        MarkdownBlock(text: "code", isCode: true), MarkdownBlock(text: "After", isCode: false),
    ])
}
