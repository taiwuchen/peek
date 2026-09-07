import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let askSelection = Self("askSelection", default: .init(.space, modifiers: [.option]))
    static let askRegion = Self("askRegion", default: .init(.space, modifiers: [.option, .shift]))
}
