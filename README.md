<p align="center">
  <img src="docs/app-icon.png" width="128" height="128" alt="Peek app icon">
</p>

<h1 align="center">Peek</h1>

<p align="center">Capture a screen region, ask AI about it, and keep talking — in a panel that floats over your work.</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-0a0a0c?style=flat-square" alt="macOS 15+">
  <img src="https://img.shields.io/badge/swift-6.0-f05138?style=flat-square" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-6e5aff?style=flat-square" alt="License: MIT"></a>
</p>

Peek is a macOS menu bar app with no Dock icon. It stays out of the way until you need it, then answers questions about whatever is on your screen without you having to describe it, screenshot it by hand, or switch to a browser tab.

## How it works

1. Press <kbd>⌥</kbd><kbd>⇧</kbd><kbd>Space</kbd> (or pick **Ask about screen region** from the menu bar) and drag over part of the screen.
2. The screenshot goes straight to your provider with the active prompt mode — no typing needed for the common case.
3. The answer streams into a floating panel. Ask follow-ups, or add more screenshots by pasting or dragging them anywhere onto the panel.

Screenshots and answers stay in the panel until you close it. Closing it ends the conversation.

## Prompt modes

A mode is a name and a prompt — "Explain" / `Explain this` ships by default. Whatever mode is active is the prompt sent with each new screenshot, so the common question costs one hotkey and one drag. Switch modes from the panel's top-left menu; add, edit, and delete them in Settings.

## Providers

Pick one in Settings. Every provider receives images.

**Hosted APIs** — you supply the key, billed to your account:

- Anthropic API
- OpenAI API
- Gemini API

**CLI subscriptions** — Peek runs a CLI you already have installed and signed in:

- Claude Code (`claude`)
- Codex (`codex`, ChatGPT subscription)

## Privacy

Peek reads your screen and talks to model providers, so the boundaries are worth stating plainly:

- **API keys live in the macOS Keychain**, never in `UserDefaults`, never in logs.
- **Peek never reads another tool's credential files.** Subscription access goes through the CLI binary, which handles its own login.
- **Screenshots are only written to disk for CLI providers**, which need a file path. They go to a per-request directory in the system temp folder created `0700` with images `0600`, and the directory is deleted when the request finishes. Hosted API providers keep screenshots in memory.
- Screenshots are sent only to the provider you selected. Peek has no backend, no telemetry, and no analytics.

## Install

Peek is pre-release: there is no signed download yet, so build it from source (below). Notarized builds will land on the [Releases](https://github.com/taiwuchen/peek/releases) page once the app settles down.

Requires **macOS 15 or later**. On first use, grant **Screen Recording** access so Peek can capture a region — the panel links straight to the right System Settings pane if the permission is missing.

Peek is not sandboxed: it needs to spawn `claude` or `codex` for the CLI providers.

## Build from source

```sh
swift build && swift test                                                # package
xcodegen generate && xcodebuild -scheme Peek -configuration Debug build  # app
```

Requires Xcode 26 (ScreenCaptureKit needs its concurrency annotations) and [xcodegen](https://github.com/yonaskolb/XcodeGen). `Peek.xcodeproj` is generated from `project.yml` and is not committed. `scripts/build-app.sh` does both steps and prints the built app path.

### Layout

`PeekKit` is a SwiftPM package; dependencies flow inward and no module depends on a sibling.

| Module | Contents |
| --- | --- |
| `Sources/PeekCore` | Shared types and protocols only — `Capture`, `AIProvider`, `CredentialStore`, `AppSettings`. No UI, no networking. |
| `Sources/PeekCapture` | `ScreenRegionCapturer` via ScreenCaptureKit. |
| `Sources/PeekProviders` | `AIProvider` implementations for the hosted APIs and the CLIs. |
| `Sources/PeekUI` | Status item, global hotkey, conversation panel, settings. |
| `App/` | Thin `@main` that wires the modules together. |

Swift 6 strict concurrency. Tests use [Swift Testing](https://github.com/swiftlang/swift-testing), not XCTest.

## License

MIT — see [LICENSE](LICENSE).
