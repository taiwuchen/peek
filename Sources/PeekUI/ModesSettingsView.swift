import KeyboardShortcuts
import PeekCore
import SwiftUI

struct ModesSettingsView: View {
    @Bindable var model: SettingsModel
    @State private var editedMode: PromptMode?
    @State private var isCreating = false

    var body: some View {
        Section("Prompt modes") {
            Picker("Active mode", selection: $model.settings.selectedModeID) {
                if model.settings.selectedMode == nil {
                    Text("Choose a mode").tag(model.settings.selectedModeID)
                }
                ForEach(model.settings.modes) { mode in
                    Text(mode.name).tag(Optional(mode.id))
                }
            }
            if let mode = model.settings.selectedMode {
                Text(mode.prompt).lineLimit(4).foregroundStyle(.secondary)
                KeyboardShortcuts.Recorder("Shortcut:", name: mode.shortcutName)
                HStack {
                    Button("Edit mode") { editedMode = mode }
                    Button("Delete mode", role: .destructive) { model.deleteMode(id: mode.id) }
                        .disabled(!model.canDeleteMode(id: mode.id))
                }
                if !model.canDeleteMode(id: mode.id) {
                    Text("Keep at least one mode with a name and prompt. Create another before deleting this one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Create or select a mode before asking about a screen region.")
                    .foregroundStyle(.secondary)
            }
            Button("New mode") { isCreating = true }
            Text("The active mode supplies the prompt for each new screen capture. A mode's shortcut selects it and starts a capture.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: $editedMode) { mode in
            ModeEditor(mode: mode) { name, prompt in
                model.updateMode(PromptMode(id: mode.id, name: name, prompt: prompt))
            }
        }
        .sheet(isPresented: $isCreating) {
            ModeEditor { name, prompt in model.addMode(name: name, prompt: prompt) }
        }
    }
}

private struct ModeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var prompt: String
    private let isNew: Bool
    private let save: (String, String) -> Bool

    init(mode: PromptMode? = nil, save: @escaping (String, String) -> Bool) {
        _name = State(initialValue: mode?.name ?? "")
        _prompt = State(initialValue: mode?.prompt ?? "")
        isNew = mode == nil
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New mode" : "Edit mode").font(.headline)
            TextField("Name", text: $name)
            Text("Prompt")
            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 160)
                .border(.separator)
                .accessibilityLabel("Prompt")
            Text("A name and prompt are required. Changes take effect when you save.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if save(name, prompt) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
