import KeyboardShortcuts
import PeekCore
import SwiftUI

struct ModesSettingsView: View {
    @Bindable var model: SettingsModel
    @State private var isCreating = false

    var body: some View {
        Section {
            Picker("Active mode", selection: $model.settings.selectedModeID) {
                if model.settings.selectedMode == nil {
                    Text("Choose a mode").tag(model.settings.selectedModeID)
                }
                ForEach(model.settings.modes) { mode in
                    Text(mode.name).tag(Optional(mode.id))
                }
            }
            if let mode = model.settings.selectedMode {
                ModeFields(mode: mode) { model.updateMode($0) }
                    .id(mode.id)
                KeyboardShortcuts.Recorder("Shortcut:", name: mode.shortcutName)
                Button("Delete mode", role: .destructive) { model.deleteMode(id: mode.id) }
                    .disabled(!model.canDeleteMode(id: mode.id))
            } else {
                Text("Create or select a mode before asking about a screen region.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Prompt modes")
                Spacer()
                Button("New mode") { isCreating = true }
            }
        }
        .sheet(isPresented: $isCreating) {
            ModeEditor { name, prompt, waitsForContext in
                model.addMode(name: name, prompt: prompt, waitsForContext: waitsForContext)
            }
        }
    }
}

/// Edits the selected mode in place; saves on every change while the name and prompt are filled in.
private struct ModeFields: View {
    @State private var name: String
    @State private var prompt: String
    @State private var waitsForContext: Bool
    private let id: UUID
    private let save: (PromptMode) -> Void

    init(mode: PromptMode, save: @escaping (PromptMode) -> Void) {
        _name = State(initialValue: mode.name)
        _prompt = State(initialValue: mode.prompt)
        _waitsForContext = State(initialValue: mode.waitsForContext)
        id = mode.id
        self.save = save
    }

    var body: some View {
        TextField("Name", text: $name)
            .onChange(of: name) { saveFields() }
        TextField("Prompt", text: $prompt, axis: .vertical)
            .lineLimit(3...10)
            .onChange(of: prompt) { saveFields() }
        Toggle("Add context before sending", isOn: $waitsForContext)
            .onChange(of: waitsForContext) { saveFields() }
    }

    private func saveFields() {
        save(PromptMode(id: id, name: name, prompt: prompt, waitsForContext: waitsForContext))
    }
}

private struct ModeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var prompt = ""
    @State private var waitsForContext = false
    let save: (String, String, Bool) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New mode").font(.headline)
            TextField("Name", text: $name)
            Text("Prompt")
            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 160)
                .border(.separator)
                .accessibilityLabel("Prompt")
            Toggle("Add context before sending", isOn: $waitsForContext)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if save(name, prompt, waitsForContext) { dismiss() }
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
