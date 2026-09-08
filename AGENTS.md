# Peek

macOS menu bar app: capture a screen region, process it with a prompt mode, and continue the conversation in a movable window. Screenshots and answers remain until the window is closed. Pre-release: no signed build published yet. Will ship signed and notarized on GitHub Releases, not the App Store. Not sandboxed.

## Layout

- `Package.swift` - SwiftPM package `PeekKit`, macOS 15+, Swift 6 strict concurrency.
- `Sources/PeekCore` - shared types and protocols only. `Capture`, `AIProvider`, `CredentialStore`, `AppSettings`. No AppKit UI, no networking.
- `Sources/PeekCapture` - `ScreenRegionCapturer` implementation (ScreenCaptureKit).
- `Sources/PeekProviders` - `AIProvider` implementations. Hosted APIs (Anthropic, OpenAI, Gemini) keyed from `CredentialStore`. CLI providers spawn the user's installed `claude` or `codex` and use their existing login.
- `Sources/PeekUI` - status item, global hotkey, conversation panel, settings window.
- `App/` - thin `@main` that wires modules together. `project.yml` generates `Peek.xcodeproj` via xcodegen; the project file is not committed.

## Rules

- Plain, concise language. No emojis. Keep comments to one line.
- Keep modules modular with clearly separated concerns. Choose the simplest implementation that fully
  meets current requirements; no speculative abstractions, configuration, or indirection.
- Do not preserve backward compatibility unless the interface is consumed outside this repo. Remove
  obsolete paths instead of adding compatibility layers, fallbacks, or migrations.
- Dependencies flow inward: `PeekCore` depends on nothing. Other modules depend on `PeekCore` only, never on each other. `App` depends on all.
- Never read another CLI's credential files. Subscription access goes through the CLI binary.
- Secrets live in Keychain via `CredentialStore`. Never in UserDefaults or logs.
- Tests use Swift Testing (`import Testing`), not XCTest.

## Build

```sh
swift build && swift test          # package
xcodegen generate && xcodebuild -scheme Peek -configuration Debug build   # app
```
