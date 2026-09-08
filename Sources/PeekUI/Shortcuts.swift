import KeyboardShortcuts
import PeekCore

extension KeyboardShortcuts.Name {
    static let askRegion = Self("askRegion", default: .init(.space, modifiers: [.option, .shift]))
}

extension PromptMode {
    /// Global shortcut that selects this mode and starts a capture. The library persists the recorded combo by this name.
    var shortcutName: KeyboardShortcuts.Name { .init("mode.\(id.uuidString)") }
}
