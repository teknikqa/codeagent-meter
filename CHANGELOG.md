# Changelog

## [1.7.1](https://github.com/teknikqa/codeagent-meter/compare/v1.7.0...v1.7.1) (2026-10-02)


### Bug Fixes

* access Keychain through the security tool to stop password prompts ([#27](https://github.com/teknikqa/codeagent-meter/issues/27)) ([11f5e5a](https://github.com/teknikqa/codeagent-meter/commit/11f5e5a8817e93c2ecff0ef43c2e3755f59f0044))
* re-authenticate cookie and OpenRouter accounts in place ([#24](https://github.com/teknikqa/codeagent-meter/issues/24)) ([868efdd](https://github.com/teknikqa/codeagent-meter/commit/868efddac0c74ec71428107a66dd23ae3c5409ca))
* sign with a stable identity so Keychain access grants persist ([#26](https://github.com/teknikqa/codeagent-meter/issues/26)) ([b01da5b](https://github.com/teknikqa/codeagent-meter/commit/b01da5ba278c9ca010d45cf980240eca74f09abf))

## [1.7.0](https://github.com/teknikqa/codeagent-meter/compare/v1.6.0...v1.7.0) (2026-09-15)


### Features

* add OpenRouter usage tracking ([#22](https://github.com/teknikqa/codeagent-meter/issues/22)) ([cd25c42](https://github.com/teknikqa/codeagent-meter/commit/cd25c42fb8fa094eae3197f732ffb55737214b2d))

## [1.6.0](https://github.com/teknikqa/codeagent-meter/compare/v1.5.0...v1.6.0) (2026-09-15)


### Features

* add Devin (Windsurf, Codeium) usage tracking ([#21](https://github.com/teknikqa/codeagent-meter/issues/21)) ([995abbf](https://github.com/teknikqa/codeagent-meter/commit/995abbf01ae5c6c61b8cf1fb808f5b9075743032))
* add Kiro usage tracking ([#19](https://github.com/teknikqa/codeagent-meter/issues/19)) ([2b84953](https://github.com/teknikqa/codeagent-meter/commit/2b849534e3169135dafd698840662e86621b3d62))

## [1.5.0](https://github.com/teknikqa/codeagent-meter/compare/v1.4.0...v1.5.0) (2026-09-15)


### Features

* show Dock icon only while a window is open ([#16](https://github.com/teknikqa/codeagent-meter/issues/16)) ([9696b9b](https://github.com/teknikqa/codeagent-meter/commit/9696b9b315c22fd91d99c0d7db5cb4148942b15d))


### Bug Fixes

* build with a compatible SDK when only Command Line Tools are installed ([#18](https://github.com/teknikqa/codeagent-meter/issues/18)) ([dd991f8](https://github.com/teknikqa/codeagent-meter/commit/dd991f8c95481b23b6b9add4f4d7cb57e0abb8bb))

## [1.4.0](https://github.com/teknikqa/codeagent-meter/compare/v1.3.0...v1.4.0) (2026-09-14)


### Features

* add Cursor usage tracking ([#14](https://github.com/teknikqa/codeagent-meter/issues/14)) ([71db952](https://github.com/teknikqa/codeagent-meter/commit/71db95209f37caa6d6971d4a29969475e2678485))

## [1.3.0](https://github.com/teknikqa/codeagent-meter/compare/v1.2.0...v1.3.0) (2026-09-14)


### Features

* add Antigravity usage tracking ([#12](https://github.com/teknikqa/codeagent-meter/issues/12)) ([d123017](https://github.com/teknikqa/codeagent-meter/commit/d1230174beb888d9f691be3bf25d4943ae0eb61d))

## [1.2.0](https://github.com/teknikqa/codeagent-meter/compare/v1.1.0...v1.2.0) (2026-09-14)


### Features

* add Codex usage tracking ([2f9d747](https://github.com/teknikqa/codeagent-meter/commit/2f9d747f34f03c6df7b8691b237df8552aa17e85))
* **app:** add account renaming from the full window ([#7](https://github.com/teknikqa/codeagent-meter/issues/7)) ([97256bc](https://github.com/teknikqa/codeagent-meter/commit/97256bc20dfb92aebbcb232172ce7bd5ce4da30d))
* group accounts under a Claude Code vendor header ([#10](https://github.com/teknikqa/codeagent-meter/issues/10)) ([d00ffa6](https://github.com/teknikqa/codeagent-meter/commit/d00ffa6e37ab72a68bd02b026d80796959c16f4a))
* show weekly (7-day) usage alongside the 5-hour session window ([#9](https://github.com/teknikqa/codeagent-meter/issues/9)) ([b7d8d6f](https://github.com/teknikqa/codeagent-meter/commit/b7d8d6f465b852ed76e81cc5b05b9aa837927415))

## [1.1.0](https://github.com/teknikqa/ai-usage-meter/compare/v1.0.0...v1.1.0) (2026-09-02)


### Features

* **app:** add account removal from the full window ([#3](https://github.com/teknikqa/ai-usage-meter/issues/3)) ([00bc0a0](https://github.com/teknikqa/ai-usage-meter/commit/00bc0a001acbb5524498b63d1451db37b16474aa))

## 1.0.0 (2026-09-02)


### Features

* **app:** add add-account flow (CLI auto-detect + paste cookie) ([8b0c020](https://github.com/teknikqa/ai-usage-meter/commit/8b0c0209e474cbf99524650233995f75a713b179))
* **app:** add full window mode (WindowGroup) ([59bff14](https://github.com/teknikqa/ai-usage-meter/commit/59bff14c1c1eb1c062f37ea0057067d278832358))
* **app:** add MenuBarExtra UI with per-account rows ([273c3a8](https://github.com/teknikqa/ai-usage-meter/commit/273c3a8ea655e9915ec942b5637119fd8bf8bc19))
* **app:** add refresh scheduler and manual refresh action ([62093f0](https://github.com/teknikqa/ai-usage-meter/commit/62093f093e447b5a29b83becdc06f413734e7d71))
* **core:** add Claude cookie client, account store, and account persistence ([cf9a031](https://github.com/teknikqa/ai-usage-meter/commit/cf9a0313ddd64108895c979ff14fb0a2b23a6870))
* **core:** add Claude OAuth usage/profile client with token refresh ([deeeb3e](https://github.com/teknikqa/ai-usage-meter/commit/deeeb3ecff156219162a8e596b6aed5b227f0fc4))
* **core:** add Keychain wrapper and Claude CLI credential reader ([76d791d](https://github.com/teknikqa/ai-usage-meter/commit/76d791de961f5c495d7ae08ece7b85bd66a2f0be))
* **core:** define UsageProvider protocol and shared usage models ([964b2f3](https://github.com/teknikqa/ai-usage-meter/commit/964b2f30e0b4f24aba35be2fdd080799d0b6ec21))


### Bug Fixes

* **app:** don't require a label to add an account, surface real onboarding errors ([bac5797](https://github.com/teknikqa/ai-usage-meter/commit/bac57977a4af53f7d2bc74c0469d8d72bfb7ee1e))
* **app:** explicitly set regular activation policy so windows can activate ([782a6dc](https://github.com/teknikqa/ai-usage-meter/commit/782a6dc2582882be23eb54b0ff41ca4ab4b9f315))
* **app:** render menu bar dropdown as a SwiftUI window and activate app when opening windows ([0b141dc](https://github.com/teknikqa/ai-usage-meter/commit/0b141dc0b2a3c377192af7a002f3d089b0aa6a27))
* **core:** accept either a bare sessionKey value or a full Cookie header ([3acb1e5](https://github.com/teknikqa/ai-usage-meter/commit/3acb1e5c0b158814a5d3cb985486847ef8d0ddf0))
* **core:** correct Claude OAuth usage response schema to verified nested shape ([d14d410](https://github.com/teknikqa/ai-usage-meter/commit/d14d410189162ca111699bc4203872467670fe68))
* **core:** surface the underlying Keychain failure when CLI credentials aren't found ([82f84af](https://github.com/teknikqa/ai-usage-meter/commit/82f84af07ab150e3487d03b354532c37526bf318))
