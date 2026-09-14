import Foundation
import SQLite3

public enum CursorError: Error {
    /// Cursor isn't installed or isn't signed in.
    case notSignedIn
    case requestFailed(Int)
    case decodingFailed
}

/// Fetches Cursor's included usage for the current billing cycle via the
/// dashboard API Cursor's own settings page uses, authenticating with the
/// login Cursor stores in its local settings database.
///
/// Read-only: the database is opened with `SQLITE_OPEN_READONLY` and re-read on
/// every fetch, so a re-login in Cursor is picked up without re-adding the account.
public struct CursorProvider: UsageProvider {
    public static let vendorID = "cursor"
    public static let displayName = "Cursor"

    private static let baseURL = "https://api2.cursor.sh/aiserver.v1.DashboardService/"
    private static var databasePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
    }

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func fetchUsage(for account: ClaudeAccount) async throws -> UsageSnapshot {
        let stored = Self.readValues(keys: ["cursorAuth/accessToken", "cursorAuth/cachedEmail"])
        guard let accessToken = stored["cursorAuth/accessToken"], !accessToken.isEmpty else {
            throw CursorError.notSignedIn
        }
        let usage = try await post("GetCurrentPeriodUsage", accessToken: accessToken)
        let planInfo = try? await post("GetPlanInfo", accessToken: accessToken)
        return try Self.snapshot(usage: usage, planInfo: planInfo, email: stored["cursorAuth/cachedEmail"])
    }

    private func post(_ method: String, accessToken: String) async throws -> Data {
        var request = URLRequest(url: URL(string: Self.baseURL + method)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw status == 401 ? CursorError.notSignedIn : CursorError.requestFailed(status)
        }
        return data
    }

    // MARK: - Response

    private struct PeriodUsage: Decodable {
        struct PlanUsage: Decodable {
            let totalPercentUsed: Double?
        }
        let billingCycleEnd: String?
        let planUsage: PlanUsage?
    }

    private struct PlanInfoResponse: Decodable {
        struct PlanInfo: Decodable { let planName: String? }
        let planInfo: PlanInfo?
    }

    /// Cursor meters one monthly pool, so it maps to the primary bar with a
    /// "Monthly" label. `billingCycleEnd` is epoch milliseconds as a string.
    static func snapshot(usage: Data, planInfo: Data?, email: String?) throws -> UsageSnapshot {
        guard let period = try? JSONDecoder().decode(PeriodUsage.self, from: usage),
              let percent = period.planUsage?.totalPercentUsed else {
            throw CursorError.decodingFailed
        }
        let plan = planInfo.flatMap { try? JSONDecoder().decode(PlanInfoResponse.self, from: $0) }?.planInfo?.planName
        let detail = [email, plan].compactMap { $0 }.joined(separator: " · ")
        return UsageSnapshot(
            percentUsed: percent,
            resetsAt: period.billingCycleEnd.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) },
            detailLabel: detail.isEmpty ? nil : detail,
            primaryLabel: "Monthly"
        )
    }

    // MARK: - Local settings database

    /// Reads string values from Cursor's VS Code-style `ItemTable` key/value store.
    static func readValues(keys: [String], databasePath: String = databasePath) -> [String: String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return [:]
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ?", -1, &statement, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        // SQLITE_TRANSIENT: have SQLite copy the bound string.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var values: [String: String] = [:]
        for key in keys {
            sqlite3_reset(statement)
            sqlite3_bind_text(statement, 1, key, -1, transient)
            if sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) {
                values[key] = String(cString: text)
            }
        }
        return values
    }
}
