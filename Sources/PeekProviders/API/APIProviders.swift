import PeekCore

public func apiProviders(credentials: any CredentialStore) -> [any AIProvider] {
    [
        AnthropicAPIProvider(credentials: credentials),
        OpenAIAPIProvider(credentials: credentials),
        GeminiAPIProvider(credentials: credentials),
    ]
}
