import Foundation

/// Reads Codex usage through `codex app-server`, the CLI's JSON-RPC mode over
/// stdio. Used when the access token in `auth.json` is rejected: the CLI
/// refreshes its own token and rewrites `auth.json`, so this app never has to
/// redeem the refresh token itself.
struct CodexAppServerClient: Sendable {
    private static let timeoutSeconds: UInt64 = 20
    /// A GUI app doesn't inherit the login shell's PATH, so common install
    /// locations are appended.
    // ponytail: fixed install dirs; add a configurable CLI path if one is ever missed.
    private static let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin"]
        .map { ($0 as NSString).expandingTildeInPath }

    func fetchUsage(codexHome: String) async throws -> UsageSnapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "-s", "read-only", "-a", "never", "app-server"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = (codexHome as NSString).expandingTildeInPath
        environment["PATH"] = ([environment["PATH"]].compactMap { $0 } + Self.extraPaths).joined(separator: ":")
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CodexError.cliUnavailable
        }
        // Terminating closes stdout, which ends the line reader below.
        let timeout = Task {
            try await Task.sleep(nanoseconds: Self.timeoutSeconds * 1_000_000_000)
            process.terminate()
        }
        defer {
            timeout.cancel()
            process.terminate()
        }

        var lines = stdout.fileHandleForReading.bytes.lines.makeAsyncIterator()

        func request(id: Int, method: String, params: [String: Any] = [:]) async throws -> Data {
            try send(["id": id, "method": method, "params": params], to: stdin)
            while let line = try await lines.next() {
                // Skip notifications and replies to other requests.
                guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      message["id"] as? Int == id else { continue }
                guard let result = message["result"] else { throw CodexError.cliRequestFailed(method) }
                return try JSONSerialization.data(withJSONObject: result)
            }
            // stdout closed: `codex` isn't installed (env exits 127), crashed, or timed out.
            throw CodexError.cliUnavailable
        }

        _ = try await request(id: 1, method: "initialize", params: ["clientInfo": ["name": "codeagent-meter", "version": "1"]])
        try send(["method": "initialized", "params": [String: Any]()], to: stdin)
        let account = try? JSONDecoder().decode(AccountResult.self, from: await request(id: 2, method: "account/read"))
        let limits = try await request(id: 3, method: "account/rateLimits/read")
        guard let rateLimits = try? JSONDecoder().decode(RateLimitsResult.self, from: limits).rateLimits else {
            throw CodexError.decodingFailed
        }

        return CodexProvider.snapshot(
            windows: [rateLimits.primary, rateLimits.secondary].compactMap { window in
                window.map { .init(usedPercent: $0.usedPercent, seconds: $0.windowDurationMins.map { $0 * 60 }, resetAt: $0.resetsAt) }
            },
            email: account?.account?.email,
            planType: account?.account?.planType ?? rateLimits.planType
        )
    }

    private func send(_ payload: [String: Any], to pipe: Pipe) throws {
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(0x0A)
        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw CodexError.cliUnavailable
        }
    }

    // MARK: - Results

    private struct AccountResult: Decodable {
        struct Account: Decodable {
            let email: String?
            let planType: String?
        }
        let account: Account?
    }

    private struct RateLimitsResult: Decodable {
        struct Window: Decodable {
            let usedPercent: Double?
            let windowDurationMins: Double?
            let resetsAt: Double?
        }
        struct RateLimits: Decodable {
            let primary: Window?
            let secondary: Window?
            let planType: String?
        }
        let rateLimits: RateLimits?
    }
}
