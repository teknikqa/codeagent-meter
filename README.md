# ai-usage-meter

A native macOS menu bar app for tracking usage/quota across AI coding agents. MVP scope is Claude only, with multiple accounts supported.

Multi-provider, multi-account, Keychain-based auth, in a simple menu bar package.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.10+ toolchain (ships with Xcode 15+, or the Command Line Tools for `swift build`/`swift run`)
- **Full Xcode** for `swift test` — `XCTest.framework` isn't part of the Command Line Tools, only Xcode itself
- [pnpm](https://pnpm.io) for the commit-lint/release tooling (not the app itself, which has zero third-party Swift dependencies)

## Build & run

```sh
swift build
swift run AIUsageMeterApp
```

Or open `Package.swift` directly in Xcode 15+ for full build/debug support — no `.xcodeproj` is checked in.

`swift run` launches a bare, unsigned executable (no `.app` bundle yet), so:
- It'll show a Dock icon during development — harmless, only fixed once `LSUIElement`/proper bundling is set up for packaging.
- Reading the Claude Code CLI's Keychain item triggers a one-time macOS access-permission prompt. If it keeps reappearing after every rebuild, ad-hoc sign the debug binary so it has a stable identity:
  ```sh
  codesign --force --deep --sign - .build/debug/AIUsageMeterApp
  ```

Code signing, notarization, and a proper `.app` bundle are future work — not needed for local use.

## How Claude auth works

Anthropic doesn't publish a usage API for personal accounts, so this app borrows credentials rather than requiring an API key:

1. **CLI-first (zero setup)**: reads the OAuth credentials Claude Code CLI already stores in the `"Claude Code-credentials"` Keychain item (falling back to `~/.claude/.credentials.json`), then calls the undocumented `api.anthropic.com/api/oauth/usage`/`/profile` endpoints. Refreshed tokens are cached in **this app's own** Keychain item — the CLI's credential item is never written to, so its own session is never touched.
2. **Manual fallback**: paste a `sessionKey` cookie from claude.ai (DevTools → Application → Cookies), validated immediately against `claude.ai/api/organizations` before an account is ever created. Stored in this app's own Keychain service — never `UserDefaults`.

Add an account from the menu bar dropdown → **Add Account…**.

## Architecture

- `Sources/AIUsageMeterCore` — vendor-agnostic logic: the `UsageProvider` protocol, Claude's provider implementation (OAuth + cookie clients), Keychain wrapper, account persistence, refresh scheduling. No SwiftUI/AppKit imports.
- `Sources/AIUsageMeterApp` — the SwiftUI app: `MenuBarExtra` scene, a full `WindowGroup` scene showing the same accounts with more detail, and onboarding UI. `AppState` is the single `ObservableObject` both scenes read from, so they can never disagree.

Adding a second provider (Codex, Gemini, Copilot) means a new `Providers/<Name>/` module conforming to `UsageProvider`, registered in `ProviderRegistry` — not built yet, this is MVP's extension seam, not a shipped feature.

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
