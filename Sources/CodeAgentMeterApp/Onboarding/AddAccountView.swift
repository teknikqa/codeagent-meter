import SwiftUI
import CodeAgentMeterCore

struct AddAccountView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var mode: Mode = .cliDetect
    @State private var label = ""
    @State private var codexHome = CodexProvider.defaultHome
    @State private var isBusy = false
    @State private var errorMessage: String?

    private enum Mode: String, CaseIterable, Identifiable {
        case cliDetect = "Detect CLI Login"
        case cookie = "Paste Session Cookie"
        case codex = "Codex CLI"
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
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 460)
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
