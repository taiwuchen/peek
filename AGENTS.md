# Peek

macOS menu bar app: capture a screen region, process it with a prompt mode, and continue the conversation in a movable window. Screenshots and answers remain until the window is closed. Pre-release: no signed build published yet. Will ship signed and notarized on GitHub Releases, not the App Store. Not sandboxed.

## Layout

- `Package.swift` - SwiftPM package `PeekKit`, macOS 15+, Swift 6 strict concurrency.
- `Sources/PeekCore` - shared types and protocols only. `Capture`, `AIProvider`, `CredentialStore`, `AppSettings`. No AppKit UI, no networking.
- `Sources/PeekCapture` - `ScreenRegionCapturer` implementation (ScreenCaptureKit).
- `Sources/PeekProviders` - `AIProvider` implementations. Hosted APIs (Anthropic, OpenAI, Gemini) keyed from `CredentialStore`. CLI providers spawn the user's installed `claude` or `codex` and use their existing login.
- `Sources/PeekUI` - status item, global hotkey, conversation panel, settings window.
- `App/` - thin `@main` that wires modules together. `project.yml` generates `Peek.xcodeproj` via xcodegen; the project file is not committed.

## Build

```sh
swift build && swift test          # package
xcodegen generate && xcodebuild -scheme Peek -configuration Debug build   # app
```

Debug builds are the QA app, Peek Dev (`com.taiwu.peek.dev`), and Release builds are prod, Peek (`com.taiwu.peek`). Each has its own settings, Keychain keys, and Screen Recording grant. Test unreleased changes in Peek Dev with `scripts/build-app.sh`; `scripts/build-release.sh` builds the prod DMG.
