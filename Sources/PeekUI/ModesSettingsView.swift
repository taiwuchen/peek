import KeyboardShortcuts
import PeekCore
import SwiftUI

/// Every mode beside its shortcut in one list; a mode opens in a drawer for editing.
struct ModesSettingsView: View {
    @Bindable var model: SettingsModel
    @State private var editing: Editing?

    private enum Editing: Equatable {
        case new
        case mode(UUID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsHeader(title: "Modes", subtitle: "Click the keys to record a shortcut. Click a mode to edit it.") {
                    Button("New Mode") { editing = .new }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
                VStack(spacing: 0) {
                    captureRow.padding(.bottom, 4)
                    ForEach(model.settings.modes) { mode in
                        modeRow(mode)
                        Divider()
                    }
                }
            }
            .settingsPage()
        }
        .accessibilityHidden(editing != nil)
        .overlay { drawer }
        .animation(.easeOut(duration: 0.18), value: editing)
    }

    private var captureRow: some View {
        HStack(spacing: 20) {
            ShortcutKeys(name: .askRegion, label: "the capture shortcut", conflict: owner)
                .frame(width: settingsLeadingColumn, alignment: .leading)
            HStack(spacing: 6) {
                Text("Capture with")
                Picker("Active mode", selection: $model.settings.selectedModeID) {
                    if model.settings.selectedMode == nil {
                        Text("Choose a mode").tag(model.settings.selectedModeID)
                    }
                    ForEach(model.settings.modes) { mode in
                        Text(mode.name).tag(Optional(mode.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 64)
        .background(settingsCardFill, in: RoundedRectangle(cornerRadius: 10))
    }

    private func modeRow(_ mode: PromptMode) -> some View {
        HStack(spacing: 20) {
            ShortcutKeys(name: mode.shortcutName, label: mode.name, conflict: owner)
                .frame(width: settingsLeadingColumn, alignment: .leading)
            Button { editing = .mode(mode.id) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(mode.name).fontWeight(.medium)
                            if mode.waitsForContext {
                                Text("Waits for context").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Text(mode.prompt)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.callout).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(mode.name)")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 60)
        .background(editing == .mode(mode.id) ? settingsCardFill : Color.clear)
    }

    @ViewBuilder private var drawer: some View {
        switch editing {
        case .new:
            SettingsDrawer(close: close) {
                ModeEditor(mode: nil, canDelete: false, save: {
                    model.addMode(name: $0.name, prompt: $0.prompt, waitsForContext: $0.waitsForContext)
                }, delete: {}, close: close)
            }
        case .mode(let id):
            if let mode = model.settings.modes.first(where: { $0.id == id }) {
                SettingsDrawer(close: close) {
                    ModeEditor(mode: mode, canDelete: model.canDeleteMode(id: id), save: { model.updateMode($0) },
                               delete: { model.deleteMode(id: id); close() }, close: close)
                        .id(id)
                }
            }
        case nil:
            EmptyView()
        }
    }

    private func close() { editing = nil }

    /// Names whatever else already uses `shortcut`: the capture shortcut or another mode.
    private func owner(of shortcut: KeyboardShortcuts.Shortcut, excluding name: KeyboardShortcuts.Name) -> String? {
        if name != .askRegion, KeyboardShortcuts.getShortcut(for: .askRegion) == shortcut {
            return "the capture shortcut"
        }
        return model.settings.modes.first {
            $0.shortcutName != name && KeyboardShortcuts.getShortcut(for: $0.shortcutName) == shortcut
        }?.name
    }
}

/// Edits a mode in the drawer. An existing mode saves on every change; a new one is added with Add.
private struct ModeEditor: View {
    let mode: PromptMode?
    let canDelete: Bool
    let save: (PromptMode) -> Bool
    let delete: () -> Void
    let close: () -> Void
    @State private var name: String
    @State private var prompt: String
    @State private var waitsForContext: Bool
    private let id: UUID

    init(mode: PromptMode?, canDelete: Bool, save: @escaping (PromptMode) -> Bool,
         delete: @escaping () -> Void, close: @escaping () -> Void) {
        self.mode = mode
        self.canDelete = canDelete
        self.save = save
        self.delete = delete
        self.close = close
        _name = State(initialValue: mode?.name ?? "")
        _prompt = State(initialValue: mode?.prompt ?? "")
        _waitsForContext = State(initialValue: mode?.waitsForContext ?? false)
        id = mode?.id ?? UUID()
    }

    private var draft: PromptMode { PromptMode(id: id, name: name, prompt: prompt, waitsForContext: waitsForContext) }
    private var promptIsEmpty: Bool { prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !promptIsEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(mode == nil ? "New Mode" : (name.isEmpty ? "Untitled mode" : name))
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if mode == nil {
                    Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                    Button("Add") { if save(draft) { close() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isValid)
                } else {
                    Button("Done", action: close)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.cancelAction)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.callout.weight(.medium))
                TextField("Name", text: $name).labelsHidden().textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt").font(.callout.weight(.medium))
                TextEditor(text: $prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 140)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
                    .accessibilityLabel("Prompt")
                if promptIsEmpty {
                    Text("Add a prompt to use this mode.").font(.callout).foregroundStyle(.orange)
                }
            }
            Toggle(isOn: $waitsForContext) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add context before sending")
                    Text("Type a note before the capture is sent.").font(.callout).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            Spacer()
            if mode != nil {
                Button("Delete Mode", role: .destructive, action: delete)
                    .buttonStyle(.borderless)
                    .foregroundStyle(canDelete ? Color.red : Color.secondary)
                    .disabled(!canDelete)
                    .help(canDelete ? "" : "Keep at least one mode with a name and a prompt.")
            }
        }
        .padding(22)
        .onChange(of: name) { saveIfExisting() }
        .onChange(of: prompt) { saveIfExisting() }
        .onChange(of: waitsForContext) { saveIfExisting() }
    }

    private func saveIfExisting() {
        if mode != nil { _ = save(draft) }
    }
}
