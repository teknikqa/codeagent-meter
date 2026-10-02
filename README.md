# CodeAgent Meter

A native macOS menu bar app for tracking usage/quota across AI coding agents. Tracks Claude Code, Codex, Antigravity, Cursor, Kiro, Devin (formerly Windsurf and Codeium), and OpenRouter, with multiple accounts per vendor.

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

Builds the app, wraps it in a minimal `CodeAgent Meter.app` bundle under `.build/` (so Dock/Cmd+Tab show a real name instead of the raw binary name), signs it, and launches it via `open`. Pass `release` as an argument to build in release mode.

For iteration without the bundle step, `swift build && swift run CodeAgentMeterApp` still works — or open `Package.swift` directly in Xcode 15+ for full build/debug support (no `.xcodeproj` is checked in). A bare `swift run` executable has no bundle, so it'll show as "CodeAgentMeterApp" in Dock/Cmd+Tab; use `scripts/run.sh` when that matters. With only the Command Line Tools and the macOS 27 SDK, a bare `swift build` fails with `plugin for module 'SwiftUIMacros' not found`; `scripts/run.sh` picks an older SDK automatically, or prefix the command with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk`.

### Keychain prompts

`scripts/run.sh` signs the bundle with a self-signed certificate, "CodeAgent Meter Local Signing", which it creates in your login keychain on first run. The certificate gives the app the same identity on every build, so macOS remembers each **Always Allow** you grant. Expect one prompt per Keychain item the first time (each pasted cookie or key, plus the Claude Code and `agy` logins), then none.

An ad-hoc signature (`codesign --sign -`, or a bare `swift run` binary) identifies the app by its binary hash instead, so every rebuild is a new app to Keychain and the prompts return. Set `CODESIGN_IDENTITY` to sign with your own certificate, or to `-` for ad-hoc. To remove the local certificate, delete it and its private key in Keychain Access.

Notarization and a distributable `.app` bundle are future work — the self-signed bundle is for local use only.

## How Claude auth works

Anthropic doesn't publish a usage API for personal accounts, so this app borrows credentials rather than requiring an API key:

1. **CLI-first (zero setup)**: reads the OAuth credentials Claude Code CLI already stores in the `"Claude Code-credentials"` Keychain item (falling back to `~/.claude/.credentials.json`), then calls the undocumented `api.anthropic.com/api/oauth/usage`/`/profile` endpoints. Refreshed tokens are cached in **this app's own** Keychain item — the CLI's credential item is never written to, so its own session is never touched.
2. **Manual fallback**: paste a `sessionKey` cookie from claude.ai (DevTools → Application → Cookies), validated immediately against `claude.ai/api/organizations` before an account is ever created. Stored in this app's own Keychain service — never `UserDefaults`.

Add an account from the menu bar dropdown → **Add Account…**.

## How Codex auth works

Reads the ChatGPT login Codex CLI stores in `$CODEX_HOME/auth.json` (default `~/.codex`) and calls the undocumented `chatgpt.com/backend-api/wham/usage` endpoint. Each Codex account is one `CODEX_HOME` directory, so separate profiles (e.g. `~/.codex-work`) are separate accounts.

The app never refreshes Codex tokens itself — OpenAI rotates refresh tokens on use, which would log the CLI out. It re-reads `auth.json` on every refresh. When OpenAI rejects the stored access token, the app runs `codex app-server` for that `CODEX_HOME` and reads usage over its JSON-RPC interface; the CLI refreshes its own token along the way. If that fails too, the account shows "Needs re-auth" until you run `codex login`.

## How Antigravity auth works

Antigravity meters two quota groups, Gemini and Claude + GPT, each with a 5-hour and a weekly limit; each group gets its own row. Usage comes from two sources, freshest first:

1. **Running Antigravity app or IDE**: the local language server's CSRF token comes from its command line (`ps`), its port from `lsof`, and quota from its `RetrieveUserQuotaSummary` endpoint. No stored credentials involved.
2. **`agy` login fallback**: when neither is open, reads the Google login `agy` stores in Keychain (service `gemini`, account `antigravity`) and calls Google's `loadCodeAssist` and `retrieveUserQuotaSummary`. Expired access tokens are refreshed with the OAuth client embedded in the installed `agy` binary; Google refresh tokens don't rotate, so `agy`'s login keeps working. Refreshed tokens are cached in **this app's own** Keychain item — `agy`'s is never written to.

The fallback triggers a macOS Keychain prompt on first use; choose **Always Allow** or it asks again on every refresh while Antigravity is closed.

## How Cursor auth works

Reads the login the Cursor app keeps in its local settings database (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, opened read-only) and calls the dashboard API behind Cursor's settings page (`api2.cursor.sh` `GetCurrentPeriodUsage` and `GetPlanInfo`). Cursor meters one pool per billing cycle, shown as a **Monthly** bar that resets at the cycle end. The database is re-read on every refresh, so signing in again in Cursor needs no change here.
## How Kiro auth works

Reads kiro-cli's login (`~/Library/Application Support/kiro-cli/data.sqlite3`, opened read-only). When kiro-cli isn't installed or signed in, it falls back to the login the Kiro IDE keeps on disk (`~/.aws/sso/cache/kiro-auth-token.json`, with the profile from `~/Library/Application Support/Kiro/User/globalStorage/kiro.kiroagent/profile.json`). It calls the usage API behind Kiro's account dashboard (`management.<profile region>.kiro.dev` `Get-Usage-Limits`). Kiro meters one credit pool per month, shown as a **Monthly** bar that resets on the plan's reset date; overage spend is excluded so the bar tops out at 100%.

Every Kiro login type works:

| Login | kiro-cli token | Profile | `TokenType` header |
| --- | --- | --- | --- |
| AWS Builder ID | `kirocli:odic:token` | stored, else Kiro's Builder ID default | `SSO_OIDC` |
| Google / GitHub | `kirocli:social:token` | in the token, else Kiro's social default | none |
| IAM Identity Center | `kirocli:odic:token` | stored after sign-in | `SSO_OIDC` |
| External IdP | `kirocli:external-idp:token` | stored after sign-in | `EXTERNAL_IDP` |

Organization logins have no default profile, so they need the profile kiro-cli (`state` row `api.codewhisperer.profile`) or the IDE (`profile.json`) saved after sign-in.

Tokens are never refreshed here, since kiro-cli and Kiro own them. When kiro-cli's token has expired, the app runs `kiro-cli chat --no-interactive /usage` once so the CLI refreshes its own token. The IDE refreshes its token only while Kiro is open.
## How Devin auth works

Devin is the renamed Windsurf (itself renamed from Codeium), so one Devin account covers all three. It reads the API key the Devin CLI stores in `~/.local/share/devin/credentials.toml`, along with the `api_server_url` it signed in against. When the CLI isn't signed in, it falls back to the key in the Devin app's settings database (`~/Library/Application Support/Devin/User/globalStorage/state.vscdb`, key `windsurfAuthStatus`, opened read-only), then a pre-rename Windsurf install's.

It calls `GetUserStatus` on the account's API server (`server.codeium.com` by default), the call the Devin app makes. Current plans show a **Daily** bar and a **Weekly** bar from the daily and weekly quotas. Older plans show a **Monthly** bar from their ACU or prompt-credit pool, resetting at the end of the plan period. Keys are re-read on every refresh, so signing in again needs no change here.
## How OpenRouter auth works

OpenRouter has no local login to read, so you paste an API key from [openrouter.ai/settings/keys](https://openrouter.ai/settings/keys); it's stored in Keychain and deleted when you remove the account. The app calls `GET /api/v1/key`, which works with any key: a key with a spending cap shows a bar named after its reset period (e.g. **Monthly**), plus today's and this month's spend. `GET /api/v1/credits` only answers management keys, so for those the app also shows the account balance, and uses credits as the bar when the key has no cap. A normal key without a cap shows spend only.

## Architecture

- `Sources/CodeAgentMeterCore` — vendor-agnostic logic: the `UsageProvider` protocol, Claude's provider implementation (OAuth + cookie clients), Keychain wrapper, account persistence, refresh scheduling. No SwiftUI/AppKit imports.
- `Sources/CodeAgentMeterApp` — the SwiftUI app: `MenuBarExtra` scene, a full `WindowGroup` scene showing the same accounts with more detail, and onboarding UI. `AppState` is the single `ObservableObject` both scenes read from, so they can never disagree.

Adding another provider (e.g. Copilot) means a new `Providers/<Name>/` module conforming to `UsageProvider`, registered in `ProviderRegistry` — see `Providers/Codex/` for a minimal example.

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
