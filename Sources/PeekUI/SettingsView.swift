import AppKit
import KeyboardShortcuts
import PeekCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        TabView {
            Form {
                KeyboardShortcuts.Recorder("Ask about screen region:", name: .askRegion)
                ModesSettingsView(model: model)
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gear") }

            Form {
                Section("Default provider and model") {
                    Picker("Provider", selection: $model.settings.provider) {
                        ForEach(model.providers, id: \.id) { provider in
                            Text(provider.displayName).tag(provider.id)
                        }
                    }
                    if model.isLoadingModels { ProgressView().controlSize(.small) }
                    Picker("Model", selection: $model.settings.model) {
                        if !model.models.contains(where: { $0.id == model.settings.model }) {
                            Text(model.settings.model.isEmpty ? "No models available" : model.settings.model)
                                .tag(model.settings.model)
                        }
                        ForEach(model.models) { Text($0.displayName).tag($0.id) }
                    }
                    .disabled(model.isLoadingModels || model.models.isEmpty)
                }
                ForEach(model.providers, id: \.id) { provider in
                    Section(provider.displayName) {
                        LabeledContent("Status", value: model.availability[provider.id]?.label ?? "Checking…")
                        if provider.id.isAPI {
                            APIKeyEditor(model: model, providerID: provider.id)
                        }
                    }
                }
                Section("CLI paths") {
                    TextField("Claude path", text: pathBinding(\.claudePath))
                    TextField("Codex path", text: pathBinding(\.codexPath))
                    Text("Leave blank to find the installed CLI automatically. Sign in using the CLI in Terminal.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                Button("Refresh provider status") { Task { await model.refreshAvailability(); await model.loadModels() } }
            }
            .formStyle(.grouped)
            .task { await model.refreshAvailability() }
            .task(id: model.settings.provider) { await model.loadModels() }
            .tabItem { Label("Providers", systemImage: "sparkles") }

            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .padding(12)
        .frame(width: 560, height: 570)
    }

    private func pathBinding(_ keyPath: WritableKeyPath<AppSettings, String?>) -> Binding<String> {
        Binding(get: { model.settings[keyPath: keyPath] ?? "" }, set: {
            model.settings[keyPath: keyPath] = $0.isEmpty ? nil : $0
        })
    }
}

private struct APIKeyEditor: View {
    let model: SettingsModel
    let providerID: ProviderID
    @State private var key = ""

    var body: some View {
        HStack {
            SecureField("New API key", text: $key)
                .onSubmit(save)
            Button("Save", action: save).disabled(key.isEmpty)
            Button("Remove") {
                model.saveKey("", for: providerID)
                key = ""
                Task { await model.refreshAvailability() }
            }
        }
    }

    private func save() {
        guard !key.isEmpty else { return }
        model.saveKey(key, for: providerID)
        if model.errorMessage == nil { key = "" }
        Task { await model.refreshAvailability() }
    }
}

struct PermissionsView: View {
    @State private var screenRecording = Permissions.screenRecordingGranted

    var body: some View {
        Form {
            Section("Screen Recording") {
                LabeledContent("Status", value: screenRecording ? "Allowed" : "Not allowed")
                Text("Capture the screen region you select.")
                HStack {
                    Button("Request access") { Permissions.requestScreenRecording(); refresh() }
                    Button("Open System Settings") { openPrivacySettings() }
                }
            }
            Button("Refresh permissions", action: refresh)
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        screenRecording = Permissions.screenRecordingGranted
    }
}

@MainActor
func openPrivacySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
        NSWorkspace.shared.open(url)
    }
}
