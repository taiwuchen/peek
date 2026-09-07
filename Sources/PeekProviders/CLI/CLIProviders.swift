import PeekCore

public func cliProviders(settings: any SettingsStore) -> [any AIProvider] {
    [ClaudeCLIProvider(settings: settings), CodexCLIProvider(settings: settings)]
}
