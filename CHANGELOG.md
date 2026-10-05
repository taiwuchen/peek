# Changelog

Notable changes to Peek. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Peek aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-10-05

Install this version by hand. From here on, Peek updates itself.

### Added

- In-app updates via Sparkle. Peek checks for a new release daily and asks before installing; the menu bar menu adds **Check for Updates...**.
- Per-mode **Add context before sending**: the screenshot waits in the composer so you can add text, images, PDFs, or text files, then press Enter to send them together.
- A Settings toggle to load your `CLAUDE.md` for the Claude Code provider. Off by default, so your customizations do not shape answers.

### Changed

- A capture waiting for context opens a compact panel with just the composer. It grows to full size when you send the first message.
- The panel opens at the cursor where your drag ends, and never covers the capture, even after a reverse drag.
- Modes are edited directly on the General tab of Settings and save as you type. **New mode** sits in the Prompt modes header.
- Settings saved by 0.1.1 reset to defaults once: re-select your provider and recreate custom modes.

### Fixed

- Text in the composer no longer wraps after a few words while a screenshot is waiting.

## [0.1.1] - 2026-09-21

### Fixed

- Release builds are signed with an Apple Development certificate. The 0.1.0 DMG was unsigned, so macOS never honored its Screen Recording grant and the app could not capture. The DMG is still not notarized.

### Added

- `scripts/build-release.sh` builds the signed Release app and DMG.

## [0.1.0] - 2026-09-12

First public version. The DMG is unsigned and not notarized. Screen Recording does not work; use 0.1.1.

### Added

- Capture a screen region with a customizable global shortcut (<kbd>⌥</kbd><kbd>⇧</kbd><kbd>Space</kbd> by default) or from the menu bar.
- Multi-turn conversation in a movable, resizable floating panel. Each capture opens its own panel; screenshots and answers persist until that panel is closed.
- Prompt modes: named name-and-prompt pairs, sent automatically with each new screenshot. Switchable from the panel, editable in Settings.
- Each mode can have its own global shortcut, which selects the mode and starts a capture.
- Add more screenshots mid-conversation by pasting or dragging them anywhere onto the panel.
- Hosted API providers: Anthropic, OpenAI, Gemini. Keys stored in the macOS Keychain.
- CLI subscription providers: Claude Code and Codex, run through the user's own installed and signed-in binary.
- Streaming answers with stop, retry, and copy.
- Answers render as GitHub-flavored Markdown (lists, headings, code blocks, tables) via MarkdownUI.
- Your messages sit on the right of the conversation, Peek's on the left. The whole panel header drags the window.
- CLI subscription providers are listed before hosted API providers in Settings.
- Debug builds are signed with an Apple Development certificate so the Screen Recording grant survives rebuilds.

[0.1.1]: https://github.com/taiwuchen/peek/releases/tag/v0.1.1
[0.1.0]: https://github.com/taiwuchen/peek/releases/tag/v0.1.0
