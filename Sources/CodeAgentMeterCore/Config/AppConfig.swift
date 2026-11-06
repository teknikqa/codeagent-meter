import Foundation

/// Non-secret app state persisted to disk. Never holds credentials — those
/// live exclusively in Keychain (see `KeychainStore`).
public struct AppConfig: Codable, Sendable {
    public var accounts: [ClaudeAccount]
    public var refreshIntervalSeconds: TimeInterval
    public var refreshMode: RefreshMode
    public var notificationsEnabled: Bool

    public init(
        accounts: [ClaudeAccount] = [],
        refreshIntervalSeconds: TimeInterval = 60,
        refreshMode: RefreshMode = .adaptive,
        notificationsEnabled: Bool = true
    ) {
        self.accounts = accounts
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.refreshMode = refreshMode
        self.notificationsEnabled = notificationsEnabled
    }

    // Hand-written so configs saved before a field existed still load; the
    // synthesized decoder would throw and `load()` would drop every account.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try c.decodeIfPresent([ClaudeAccount].self, forKey: .accounts) ?? []
        refreshIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .refreshIntervalSeconds) ?? 60
        refreshMode = try c.decodeIfPresent(RefreshMode.self, forKey: .refreshMode) ?? .adaptive
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
    }
}

public struct AppConfigStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL = AppConfigStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("codeagent-meter", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }

    public func save(_ config: AppConfig) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}
