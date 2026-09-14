import Foundation

/// Reads quota from the language server a running Antigravity app or IDE
/// starts on localhost. The server's CSRF token is on its command line, and
/// its HTTPS port uses a self-signed certificate.
struct AntigravityLocalServerClient: Sendable {
    private static let servicePath = "/exa.language_server_pb.LanguageServerService/"
    private static let session = URLSession(
        configuration: .ephemeral,
        delegate: LoopbackTrustDelegate(),
        delegateQueue: nil
    )

    struct Server: Equatable {
        let pid: String
        let csrfToken: String
    }

    /// Returns nil when no server is running or none answers — the caller falls back.
    func fetchUsage() async -> UsageSnapshot? {
        for server in Self.parseServers(psOutput: Self.run("/bin/ps", ["-ax", "-o", "pid=,command="])) {
            let lsofOutput = Self.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", server.pid])
            for port in Self.parsePorts(lsofOutput: lsofOutput) {
                guard let summary = await post("RetrieveUserQuotaSummary", port: port, csrfToken: server.csrfToken) else {
                    continue
                }
                let status = await post("GetUserStatus", port: port, csrfToken: server.csrfToken)
                if let snapshot = try? AntigravityProvider.snapshot(
                    fromQuotaSummary: summary,
                    detailLabel: status.flatMap(Self.detailLabel(fromUserStatus:))
                ) {
                    return snapshot
                }
            }
        }
        return nil
    }

    private func post(_ method: String, port: Int, csrfToken: String) async -> Data? {
        guard let url = URL(string: "https://127.0.0.1:\(port)\(Self.servicePath)\(method)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        guard let (data, response) = try? await Self.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    // MARK: - Discovery

    static func parseServers(psOutput: String) -> [Server] {
        psOutput.split(separator: "\n").compactMap { line in
            guard line.contains("language_server"),
                  let tokenRange = line.range(of: #"--csrf_token[ =](\S+)"#, options: .regularExpression),
                  let pid = line.split(separator: " ").first else { return nil }
            let token = line[tokenRange].dropFirst("--csrf_token ".count)
            return Server(pid: String(pid), csrfToken: String(token))
        }
    }

    static func parsePorts(lsofOutput: String) -> [Int] {
        lsofOutput.split(separator: "\n").compactMap { line in
            guard let range = line.range(of: #":\d+ \(LISTEN\)"#, options: .regularExpression) else { return nil }
            return Int(line[range].dropFirst().prefix { $0.isNumber })
        }
    }

    private static func detailLabel(fromUserStatus data: Data) -> String? {
        struct Status: Decodable {
            struct UserStatus: Decodable {
                struct PlanStatus: Decodable {
                    struct PlanInfo: Decodable { let planName: String? }
                    let planInfo: PlanInfo?
                }
                let email: String?
                let planStatus: PlanStatus?
            }
            let userStatus: UserStatus?
        }
        guard let status = (try? JSONDecoder().decode(Status.self, from: data))?.userStatus else { return nil }
        let parts = [status.email, status.planStatus?.planInfo?.planName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Accepts the language server's self-signed certificate, for loopback only.
private final class LoopbackTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.host == "127.0.0.1",
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
