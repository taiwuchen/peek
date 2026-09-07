import Foundation
import Observation
import PeekCore

@MainActor @Observable
final class SettingsModel {
    let providers: [any AIProvider]
    var settings: AppSettings { didSet { store.save(settings) } }
    private(set) var availability: [ProviderID: ProviderAvailability] = [:]
    private(set) var models: [AIModel] = []
    private(set) var isLoadingModels = false
    var errorMessage: String?
    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let credentials: any CredentialStore
    @ObservationIgnored private var modelGeneration = UUID()

    init(providers: [any AIProvider], store: any SettingsStore, credentials: any CredentialStore) {
        self.providers = providers
        self.store = store
        self.credentials = credentials
        settings = store.load()
    }

    func refreshAvailability() async {
        for provider in providers {
            let status = await provider.availability()
            guard !Task.isCancelled else { return }
            availability[provider.id] = status
        }
    }

    func loadModels() async {
        let token = UUID()
        modelGeneration = token
        models = []
        errorMessage = nil
        isLoadingModels = true
        defer { if modelGeneration == token { isLoadingModels = false } }
        guard let provider = providers.first(where: { $0.id == settings.provider }) else { return }
        do {
            let result = try await provider.models()
            guard modelGeneration == token, !Task.isCancelled else { return }
            models = result
            if !result.contains(where: { $0.id == settings.model }) {
                settings.model = result.first?.id ?? ""
            }
        } catch {
            guard modelGeneration == token, !Task.isCancelled else { return }
            errorMessage = providerErrorMessage(error)
        }
    }

    func saveKey(_ value: String, for id: ProviderID) {
        do {
            try credentials.setAPIKey(value.isEmpty ? nil : value, for: id)
            errorMessage = nil
        } catch {
            errorMessage = "Could not save the API key to Keychain. Please try again."
        }
    }
}

extension ProviderID {
    var isAPI: Bool { self == .anthropicAPI || self == .openAIAPI || self == .geminiAPI }
}

extension ProviderAvailability {
    var label: String {
        switch self {
        case .ready: "Ready"
        case .needsAPIKey: "Needs API key"
        case .cliNotInstalled: "CLI not installed"
        case .cliNotLoggedIn: "Not logged in"
        case .unavailable(let reason): reason
        }
    }
}
