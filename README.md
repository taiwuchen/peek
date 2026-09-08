<p align="center">
  <img src="docs/app-icon.png" width="128" height="128" alt="Peek app icon">
</p>

<h1 align="center">Peek</h1>

<p align="center">Select text or a screen region, press a hotkey, ask AI, and read the answer in a panel next to the content.</p>

Peek is a macOS menu bar app. It stays out of the way until you need it, then shows the answer anchored beside what you selected instead of in a separate chat window.

## How it works

1. Select text in any app, or press the region hotkey and drag over part of the screen.
2. Press the hotkey. Option-Space asks about the selection, Option-Shift-Space asks about a screen region.
3. Type a question, or send the content as is. The answer appears in a panel next to the content.

## Providers

- Hosted APIs: Anthropic, OpenAI, Gemini. API keys are stored in the macOS Keychain.
- CLI subscriptions: Peek can run your installed `claude` or `codex` command and use its existing login. It never reads another tool's credential files.

## Install

Download the latest DMG from the Releases page, open it, and drag Peek to Applications. The app is notarized and is not sandboxed. On first use, grant Accessibility access for text selection and Screen Recording access for region capture.

Requires macOS 15 or later.

## Build from source

```sh
swift build && swift test                                                # package
xcodegen generate && xcodebuild -scheme Peek -configuration Debug build  # app
```

Requires Xcode 16 and [xcodegen](https://github.com/yonaskolb/XcodeGen). The Xcode project is generated from `project.yml` and is not committed.
