import Foundation

public enum KeychainError: Error, Equatable {
    case itemNotFound
    case unexpectedData
    /// The exit status of `/usr/bin/security`.
    case osStatus(Int32)
}

/// Thin wrapper over generic-password Keychain items, scoped to a single
/// Keychain service (an app's own secrets).
///
/// Goes through `/usr/bin/security` rather than the Security framework.
/// Keychain ties an item's access to the code that asks for it, and without
/// an Apple-issued signing certificate this app's identity is its binary
/// hash, so every rebuild re-prompted for the login password on every item.
/// `security` is Apple-signed, so its access never changes, and it is how
/// the vendor CLIs whose logins this app borrows store theirs.
///
/// The cost: any process running as the user can read these items the same
/// way, without a prompt. Switch back to `SecItem*` once the app ships with
/// a Developer ID, which gives it a stable identity of its own.
public struct KeychainStore: Sendable {
    private static let securityTool = URL(fileURLWithPath: "/usr/bin/security")
    /// `security`'s exit status for `errSecItemNotFound`.
    private static let itemNotFoundStatus: Int32 = 44

    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func readData(account: String) throws -> Data {
        try Self.readData(service: service, account: account)
    }

    public func write(data: Data, account: String) throws {
        // Sent on stdin to `security -i` so the secret never appears in the
        // process list, and hex-encoded (-X) so it needs no shell quoting.
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let command = "add-generic-password -U -s \"\(service)\" -a \"\(account)\" -X \(hex)\n"
        let result = try Self.run(["-i"], input: Data(command.utf8))
        guard result.status == 0 else { throw KeychainError.osStatus(result.status) }
        // `security -i` exits 0 even when the command it ran failed.
        guard (try? readData(account: account)) == data else { throw KeychainError.unexpectedData }
    }

    public func delete(account: String) throws {
        let status = try Self.run(["delete-generic-password", "-s", service, "-a", account]).status
        guard status == 0 || status == Self.itemNotFoundStatus else {
            throw KeychainError.osStatus(status)
        }
    }

    /// Reads a generic-password item filtered by service and account.
    public static func readData(service: String, account: String) throws -> Data {
        try lookup(["-s", service, "-a", account])
    }

    /// Reads the first generic-password item matching a service, regardless of its
    /// account attribute. Used to read Keychain items owned by other apps (e.g. the
    /// Claude Code CLI) whose exact account name isn't known to us.
    public static func readFirstData(service: String) throws -> Data {
        try lookup(["-s", service])
    }

    /// `-w` prints the secret followed by a newline. It prints hex instead
    /// when the secret isn't printable text, which nothing stored through
    /// here is: cookies, API keys and JSON are all ASCII.
    private static func lookup(_ query: [String]) throws -> Data {
        let result = try run(["find-generic-password"] + query + ["-w"])
        guard result.status != itemNotFoundStatus else { throw KeychainError.itemNotFound }
        guard result.status == 0 else { throw KeychainError.osStatus(result.status) }
        guard result.output.last == UInt8(ascii: "\n") else { throw KeychainError.unexpectedData }
        return result.output.dropLast()
    }

    private static func run(_ arguments: [String], input: Data? = nil) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = securityTool
        process.arguments = arguments
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        if let input { stdin.fileHandleForWriting.write(input) }
        stdin.fileHandleForWriting.closeFile()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}
