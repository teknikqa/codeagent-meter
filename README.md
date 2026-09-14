# CodeAgent Meter

A native macOS menu bar app for tracking usage/quota across AI coding agents. Tracks Claude Code and Codex, with multiple accounts per vendor.

Multi-provider, multi-account, Keychain-based auth, in a simple menu bar package.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.10+ toolchain (ships with Xcode 15+, or the Command Line Tools for `swift build`/`swift run`)
- **Full Xcode** for `swift test` — `XCTest.framework` isn't part of the Command Line Tools, only Xcode itself
- [pnpm](https://pnpm.io) for the commit-lint/release tooling (not the app itself, which has zero third-party Swift dependencies)

## Build & run

```sh
./scripts/run.sh
```

Builds the app, wraps it in a minimal `CodeAgent Meter.app` bundle under `.build/` (so Dock/Cmd+Tab show a real name instead of the raw binary name), ad-hoc signs it, and launches it via `open`. Pass `release` as an argument to build in release mode.

For iteration without the bundle step, `swift build && swift run CodeAgentMeterApp` still works — or open `Package.swift` directly in Xcode 15+ for full build/debug support (no `.xcodeproj` is checked in). A bare `swift run` executable has no bundle, so it'll show as "CodeAgentMeterApp" in Dock/Cmd+Tab; use `scripts/run.sh` when that matters.

Either way, reading the Claude Code CLI's Keychain item triggers a one-time macOS access-permission prompt. If it keeps reappearing after every rebuild, that's because the binary's signing identity changed — `scripts/run.sh` re-signs on every run so this shouldn't recur; for a bare `swift run` binary, sign it manually:
```sh
codesign --force --deep --sign - .build/debug/CodeAgentMeterApp
```

Notarization and a properly-signed, distributable `.app` bundle are future work — `scripts/run.sh`'s bundle is unsigned beyond ad-hoc, for local use only.

## How Claude auth works

Anthropic doesn't publish a usage API for personal accounts, so this app borrows credentials rather than requiring an API key:

1. **CLI-first (zero setup)**: reads the OAuth credentials Claude Code CLI already stores in the `"Claude Code-credentials"` Keychain item (falling back to `~/.claude/.credentials.json`), then calls the undocumented `api.anthropic.com/api/oauth/usage`/`/profile` endpoints. Refreshed tokens are cached in **this app's own** Keychain item — the CLI's credential item is never written to, so its own session is never touched.
2. **Manual fallback**: paste a `sessionKey` cookie from claude.ai (DevTools → Application → Cookies), validated immediately against `claude.ai/api/organizations` before an account is ever created. Stored in this app's own Keychain service — never `UserDefaults`.

Add an account from the menu bar dropdown → **Add Account…**.

## How Codex auth works

Reads the ChatGPT login Codex CLI stores in `$CODEX_HOME/auth.json` (default `~/.codex`) and calls the undocumented `chatgpt.com/backend-api/wham/usage` endpoint. Each Codex account is one `CODEX_HOME` directory, so separate profiles (e.g. `~/.codex-work`) are separate accounts.

The app never refreshes Codex tokens itself — OpenAI rotates refresh tokens on use, which would log the CLI out. It re-reads `auth.json` on every refresh. When OpenAI rejects the stored access token, the app runs `codex app-server` for that `CODEX_HOME` and reads usage over its JSON-RPC interface; the CLI refreshes its own token along the way. If that fails too, the account shows "Needs re-auth" until you run `codex login`.

## Architecture

- `Sources/CodeAgentMeterCore` — vendor-agnostic logic: the `UsageProvider` protocol, Claude's provider implementation (OAuth + cookie clients), Keychain wrapper, account persistence, refresh scheduling. No SwiftUI/AppKit imports.
- `Sources/CodeAgentMeterApp` — the SwiftUI app: `MenuBarExtra` scene, a full `WindowGroup` scene showing the same accounts with more detail, and onboarding UI. `AppState` is the single `ObservableObject` both scenes read from, so they can never disagree.

Adding another provider (Gemini, Copilot) means a new `Providers/<Name>/` module conforming to `UsageProvider`, registered in `ProviderRegistry` — see `Providers/Codex/` for a minimal example.

## Non-goals for MVP

- No usage history or charting — the window shows the current live snapshot only.
- No adaptive/backoff refresh scheduling — a fixed 60s interval, configurable via `AppConfig.refreshIntervalSeconds`.
- No Admin API (org-level `cost_report`/`usage_report`) client, even though the `.adminKey` account kind exists in the data model — no onboarding flow creates one yet.

## Commit conventions & releases

Commits must follow [Conventional Commits](https://www.conventionalcommits.org) — enforced locally by a commitlint Husky hook on every commit. Install the Node tooling once with:

```sh
pnpm install
```

[release-please](https://github.com/googleapis/release-please) runs in CI on pushes to `main`, opening/updating a release PR that bumps the version and regenerates `CHANGELOG.md` from merged commits. For an ad-hoc local preview without waiting on CI:

```sh
pnpm exec conventional-changelog -p conventionalcommits
```
