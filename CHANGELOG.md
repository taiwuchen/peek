# Changelog

Notable changes to Peek. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Peek aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

First public version. No signed build has been published yet.

### Added

- Capture a screen region with a global hotkey (<kbd>⌥</kbd><kbd>⇧</kbd><kbd>Space</kbd>) or from the menu bar.
- Multi-turn conversation in a movable, resizable floating panel. Each capture opens its own panel; screenshots and answers persist until that panel is closed.
- Prompt modes: named name-and-prompt pairs, sent automatically with each new screenshot. Switchable from the panel, editable in Settings.
- Add more screenshots mid-conversation by pasting or dragging them anywhere onto the panel.
- Hosted API providers: Anthropic, OpenAI, Gemini. Keys stored in the macOS Keychain.
- CLI subscription providers: Claude Code and Codex, run through the user's own installed and signed-in binary.
- Streaming answers with stop, retry, and copy.
