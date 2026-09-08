# Security policy

## Supported versions

Peek is pre-release. Only the latest commit on `master` is supported.

## Reporting a vulnerability

Please report security issues privately through GitHub's
[private vulnerability reporting](https://github.com/taiwuchen/peek/security/advisories/new)
rather than opening a public issue.

Include what you did, what happened, and the macOS version. A proof of concept helps but is not required.
Expect a first reply within a week. Please give a fix a reasonable window before disclosing publicly.

## Scope

Peek captures the screen, holds model-provider API keys, and spawns local CLI binaries, so these are
the areas most worth scrutiny:

- **Credentials.** API keys belong in the macOS Keychain via `CredentialStore` and must never reach
  `UserDefaults`, logs, argument vectors, or environment variables of spawned processes.
- **Screenshots on disk.** CLI providers need a file path, so each request gets a directory under the
  system temp folder created `0700` with images written `0600`, removed when the request finishes
  (`Sources/PeekProviders/CLI/CLIRequestDirectory.swift`). Hosted API providers keep screenshots in
  memory. A path that leaves a screenshot readable or undeleted is a bug worth reporting.
- **Other tools' credentials.** Peek must never read another tool's credential files. Subscription
  access goes through the CLI binary, which handles its own login.
- **Subprocess handling.** Peek is not sandboxed and launches `claude` or `codex`. Anything that lets
  untrusted input influence which binary runs, or its arguments, is in scope.

Peek has no backend, no telemetry, and no analytics. Screenshots go only to the provider selected in
Settings.
