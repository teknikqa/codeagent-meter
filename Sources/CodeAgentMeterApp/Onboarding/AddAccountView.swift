import SwiftUI
import CodeAgentMeterCore

struct AddAccountView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var mode: Mode = .cliDetect
    @State private var label = ""
    @State private var codexHome = CodexProvider.defaultHome
    @State private var openRouterKey = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    private enum Mode: String, CaseIterable, Identifiable {
        case cliDetect = "Detect CLI Login"
        case cookie = "Paste Session Cookie"
        case codex = "Codex CLI"
        case antigravity = "Antigravity"
        case cursor = "Cursor"
        case kiro = "Kiro"
        case devin = "Devin"
        case openRouter = "OpenRouter"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Account")
                .font(.headline)

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Label (optional, e.g. Work, Personal)", text: $label)
                .textFieldStyle(.roundedBorder)

            switch mode {
            case .cliDetect:
                Text("Reads the login Claude Code CLI already stored in Keychain — no setup needed if you're logged into `claude` on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Add Account") {
                    addCLIAccount()
                }
                .disabled(isBusy)
            case .cookie:
                PasteCookieView(onSubmit: addCookieAccount, isBusy: isBusy)
            case .codex:
                Text("Reads the login Codex CLI stored in `auth.json` under this directory. Use a different path (e.g. `~/.codex-work`) for another `CODEX_HOME`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Codex home", text: $codexHome)
                    .textFieldStyle(.roundedBorder)
                Button("Add Account") {
                    addCodexAccount()
                }
                .disabled(isBusy || codexHome.isEmpty)
            case .antigravity:
                Text("Reads quota from the running Antigravity app or IDE. When neither is open, falls back to the Google login `agy` stored in Keychain — macOS asks for access the first time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Add Account") {
                    addAntigravityAccount()
                }
                .disabled(isBusy)
            case .cursor:
                Text("Reads the login the Cursor app stores locally — no setup needed if you're signed in to Cursor on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Add Account") {
                    addCursorAccount()
                }
                .disabled(isBusy)
            case .kiro:
                Text("Reads the login kiro-cli stores locally, or the Kiro app's if kiro-cli isn't signed in — no setup needed if you're signed in to either on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Add Account") {
                    addKiroAccount()
                }
                .disabled(isBusy)
            case .devin:
                Text("Reads the API key the Devin CLI stores locally, or the Devin (formerly Windsurf) app's if the CLI isn't signed in — no setup needed if you're signed in to either on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Add Account") {
                    addDevinAccount()
                }
                .disabled(isBusy)
            case .openRouter:
                Text("Paste an API key from openrouter.ai/settings/keys. A key with a spending cap shows that cap; a management key also shows your credit balance. The key is stored in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("sk-or-v1-…", text: $openRouterKey)
                    .textFieldStyle(.roundedBorder)
                Button("Add Account") {
                    addOpenRouterAccount()
                }
                .disabled(isBusy || openRouterKey.isEmpty)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 780)
    }

    private func addCLIAccount() {
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                _ = try ClaudeCLICredentialReader().readCredentials()
                let id = UUID()
                let resolvedLabel = label.isEmpty ? "Claude Code CLI" : label
                let account = ClaudeAccount(id: id, label: resolvedLabel, authKind: .cliKeychain, keychainKey: id.uuidString)
                try await appState.addAccount(account)
                await appState.refreshAll()
                dismissWindow(id: "add-account")
            } catch {
                errorMessage = "Couldn't read the Claude Code CLI login: \(error)"
            }
        }
    }

    private func addCodexAccount() {
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                let id = UUID()
                var account = ClaudeAccount(id: id, label: label, authKind: .codexCLI, keychainKey: id.uuidString, codexHome: codexHome)
                let snapshot = try await CodexProvider().fetchUsage(for: account)
                if label.isEmpty {
                    account.label = snapshot.detailLabel?.components(separatedBy: " · ").first ?? "Codex CLI"
                }
                try await appState.addAccount(account)
                await appState.refreshAll()
                dismissWindow(id: "add-account")
            } catch {
                errorMessage = "Couldn't read the Codex CLI login at \(codexHome): \(error)"
            }
        }
    }

    private func addAntigravityAccount() {
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                let id = UUID()
                let account = ClaudeAccount(id: id, label: label.isEmpty ? "Antigravity" : label, authKind: .antigravity, keychainKey: id.uuidString)
                _ = try await AntigravityProvider().fetchUsage(for: account)
                try await appState.addAccount(account)
                await appState.refreshAll()
                dismissWindow(id: "add-account")
            } catch {
                errorMessage = "Couldn't read Antigravity usage — open Antigravity or sign in to agy: \(error)"
            }
        }
    }

    private func addCursorAccount() {
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                let id = UUID()
                var account = ClaudeAccount(id: id, label: label, authKind: .cursor, keychainKey: id.uuidString)
                let snapshot = try await CursorProvider().fetchUsage(for: account)
                if label.isEmpty {
                    account.label = snapshot.detailLabel?.components(separatedBy: " · ").first ?? "Cursor"
                }
                try await appState.addAccount(account)
                await appState.refreshAll()
                dismissWindow(id: "add-account")
            } catch {
                errorMessage = "Couldn't read Cursor usage — sign in to Cursor first: \(error)"
            }
        }
    }

    private func addKiroAccount() {
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                let id = UUID()
                let account = ClaudeAccount(id: id, label: label.isEmpty ? "Kiro" : label, authKind: .kiro, keychainKey: id.uuidString)
                _ = try await KiroProvider().fetchUsage(for: account)
                try await appState.addAccount(account)
                await appState.refreshAll()
                dismissWindow(id: "add-account")
            } catch {
                errorMessage = "Couldn't read Kiro usage — run kiro-cli login or sign in to Kiro first: \(error)"
            }
        }
    }

    private func addDevinAccount() {
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                let id = UUID()
                var account = ClaudeAccount(id: id, label: label, authKind: .devin, keychainKey: id.uuidString)
                let snapshot = try await DevinProvider().fetchUsage(for: account)
                if label.isEmpty {
                    account.label = snapshot.detailLabel?.components(separatedBy: " · ").first ?? "Devin"
                }
                try await appState.addAccount(account)
                await appState.refreshAll()
                dismissWindow(id: "add-account")
            } catch {
                errorMessage = "Couldn't read Devin usage — run devin auth login or sign in to Devin first: \(error)"
            }
        }
    }

    private func addOpenRouterAccount() {
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                let provider = OpenRouterProvider()
                _ = try await provider.fetchUsage(apiKey: openRouterKey)
                let id = UUID()
                let account = ClaudeAccount(id: id, label: label.isEmpty ? "OpenRouter" : label, authKind: .openRouter, keychainKey: id.uuidString)
                try provider.storeKey(openRouterKey, account: account)
                try await appState.addAccount(account)
                await appState.refreshAll()
                dismissWindow(id: "add-account")
            } catch {
                errorMessage = "That OpenRouter key didn't work: \(error)"
            }
        }
    }

    private func addCookieAccount(_ sessionKey: String) {
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                let cookieClient = ClaudeCookieClient()
                let discovered = try await cookieClient.validateAndDiscoverOrganization(sessionKey: sessionKey)
                let id = UUID()
                let resolvedLabel = label.isEmpty ? discovered.orgName : label
                let account = ClaudeAccount(
                    id: id,
                    label: resolvedLabel,
                    authKind: .cookie,
                    keychainKey: id.uuidString,
                    orgId: discovered.orgId
                )
                try cookieClient.storeSessionKey(sessionKey, account: account)
                try await appState.addAccount(account)
                await appState.refreshAll()
                dismissWindow(id: "add-account")
            } catch {
                errorMessage = "That session cookie didn't work: \(error)"
            }
        }
    }
}
