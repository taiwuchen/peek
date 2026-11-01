import AppKit
import PeekCore
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case modes, providers, permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .modes: "Modes"
        case .providers: "Providers"
        case .permissions: "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .modes: "keyboard"
        case .providers: "sparkles"
        case .permissions: "lock.shield"
        }
    }
}

/// Width of the leading column that holds shortcuts and statuses on every settings page.
let settingsLeadingColumn: CGFloat = 170
/// Fill for highlighted rows and summary cards.
let settingsCardFill = Color.primary.opacity(0.045)

struct SettingsView: View {
    @Bindable var model: SettingsModel
    @State private var section = SettingsSection.modes

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { section }, set: { if let new = $0 { section = new } })) {
                ForEach(SettingsSection.allCases) { item in
                    Label(item.title, systemImage: item.icon).tag(item)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .padding(.top, 36)
            .frame(width: 200)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            Group {
                switch section {
                case .modes: ModesSettingsView(model: model)
                case .providers: ProvidersSettingsView(model: model)
                case .permissions: PermissionsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 860, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

/// Page title with a one-line description and an optional trailing action.
struct SettingsHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

/// A panel that slides over the page from the trailing edge.
struct SettingsDrawer<Content: View>: View {
    let close: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.06)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            content
                .frame(width: 320)
                .frame(maxHeight: .infinity, alignment: .top)
                .background {
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 14, x: -6)
                }
                .overlay(alignment: .leading) { Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1) }
                .transition(.move(edge: .trailing))
        }
        .transition(.opacity)
    }
}

/// A small coloured dot beside a status word.
struct StatusLabel: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(text).font(.callout)
        }
    }
}

extension View {
    /// Shared padding for a settings page; the top clears the transparent title bar.
    func settingsPage() -> some View {
        padding(.horizontal, 32).padding(.top, 40).padding(.bottom, 32)
    }
}

struct ProvidersSettingsView: View {
    @Bindable var model: SettingsModel
    @State private var openID: ProviderID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsHeader(title: "Providers", subtitle: "Subscriptions use your signed-in CLI. API keys stay in Keychain.") {
                    Button("Refresh") { Task { await model.refreshAvailability(); await model.loadModels() } }
                        .buttonBorderShape(.capsule)
                }
                defaultRow
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                VStack(spacing: 0) {
                    ForEach(model.providers, id: \.id) { provider in
                        row(provider)
                        Divider()
                    }
                }
            }
            .settingsPage()
        }
        .accessibilityHidden(openID != nil)
        .overlay {
            if let provider = model.providers.first(where: { $0.id == openID }) {
                SettingsDrawer(close: { openID = nil }) {
                    ProviderDetail(model: model, provider: provider) { openID = nil }
                        .id(provider.id)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: openID)
        .task { await model.refreshAvailability() }
        .task(id: model.settings.provider) { await model.loadModels() }
    }

    private var defaultRow: some View {
        HStack(spacing: 6) {
            Text("New captures use")
            Picker("Provider", selection: $model.settings.provider) {
                ForEach(model.providers, id: \.id) { provider in
                    Text(provider.displayName).tag(provider.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            Text("with")
            Picker("Model", selection: $model.settings.model) {
                if !model.models.contains(where: { $0.id == model.settings.model }) {
                    Text(model.settings.model.isEmpty ? "No models available" : model.settings.model)
                        .tag(model.settings.model)
                }
                ForEach(model.models) { Text($0.displayName).tag($0.id) }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(model.isLoadingModels || model.models.isEmpty)
            if model.isLoadingModels { ProgressView().controlSize(.small) }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(settingsCardFill, in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ provider: any AIProvider) -> some View {
        let availability = model.availability[provider.id]
        return HStack(spacing: 20) {
            StatusLabel(text: availability?.label ?? "Checking…", color: availability == .ready ? .green : .secondary)
                .frame(width: settingsLeadingColumn, alignment: .leading)
            Button { openID = provider.id } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(provider.displayName).fontWeight(.medium)
                            if model.settings.provider == provider.id {
                                Text("Default").font(.callout).foregroundStyle(.tint)
                            }
                        }
                        Text(summary(provider.id, ready: availability == .ready))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.callout).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set up \(provider.displayName)")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 58)
        .background(openID == provider.id ? settingsCardFill : Color.clear)
    }

    private func summary(_ id: ProviderID, ready: Bool) -> String {
        switch id {
        case .claudeCLI: "Uses your Claude login through the claude CLI"
        case .codexCLI: "Uses your ChatGPT login through the codex CLI"
        default: ready ? "API key saved in Keychain" : "Pay per use with your own API key"
        }
    }
}

/// One provider's key, CLI path and options, shown in the drawer.
private struct ProviderDetail: View {
    @Bindable var model: SettingsModel
    let provider: any AIProvider
    let close: () -> Void

    var body: some View {
        let availability = model.availability[provider.id]
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(provider.displayName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            }
            StatusLabel(text: availability?.label ?? "Checking…", color: availability == .ready ? .green : .secondary)
            if provider.id.isAPI {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API key").font(.callout.weight(.medium))
                    APIKeyEditor(model: model, providerID: provider.id)
                    Text("Stored in Keychain, never in Peek's settings.").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let path = cliPath {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CLI path").font(.callout.weight(.medium))
                    TextField("Find automatically", text: pathBinding(path)).textFieldStyle(.roundedBorder)
                    Text("Leave blank to find the installed CLI automatically. Sign in using the CLI in Terminal.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if provider.id == .claudeCLI {
                Toggle(isOn: $model.settings.claudeIgnoresInstructions) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ignore CLAUDE.md and customizations")
                        Text("Skips CLAUDE.md, skills, plugins, hooks, MCP servers, and output styles.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }
            if model.settings.provider != provider.id {
                Button("Use for New Captures") { model.settings.provider = provider.id }
            }
            Spacer()
        }
        .padding(22)
    }

    private var cliPath: WritableKeyPath<AppSettings, String?>? {
        switch provider.id {
        case .claudeCLI: \.claudePath
        case .codexCLI: \.codexPath
        default: nil
        }
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
        VStack(alignment: .leading, spacing: 8) {
            SecureField("Paste API key", text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Button("Save Key", action: save).disabled(key.isEmpty)
                Button("Remove Key", role: .destructive) {
                    model.saveKey("", for: providerID)
                    key = ""
                    Task { await model.refreshAvailability() }
                }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsHeader(title: "Permissions", subtitle: "Peek reads the screen only while you drag out a region.") {
                    EmptyView()
                }
                HStack(spacing: 20) {
                    StatusLabel(text: screenRecording ? "Allowed" : "Not allowed", color: screenRecording ? .green : .red)
                        .frame(width: settingsLeadingColumn, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen Recording").fontWeight(.medium)
                        Text(screenRecording ? "Peek checks again each time you come back to this window."
                                             : "Turn on Peek in Privacy & Security › Screen & System Audio Recording.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if !screenRecording {
                        Button("Request Access") { Permissions.requestScreenRecording(); refresh() }
                        Button("Open System Settings") { openPrivacySettings() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                .background(settingsCardFill, in: RoundedRectangle(cornerRadius: 10))
                VStack(spacing: 0) {
                    fact("Screenshots", "Stay with their conversation and are gone when you close its window.")
                    fact("Sent to", "Only the provider you chose, when a message is sent.")
                    fact("API keys", "In your Keychain, never in Peek's settings.")
                }
            }
            .settingsPage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onAppear(perform: refresh)
    }

    private func fact(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(title).font(.callout).foregroundStyle(.secondary)
                    .frame(width: settingsLeadingColumn, alignment: .leading)
                Text(detail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            Divider()
        }
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
