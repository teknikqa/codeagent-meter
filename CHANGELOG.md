# Changelog

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
