import Foundation

public struct ProviderStatus: Equatable, Sendable {
    public enum Indicator: String, Sendable { case none, minor, major, critical, maintenance }

    public let indicator: Indicator
    public let description: String
    public var isIncident: Bool { indicator != .none }
}

/// Polls vendors' public Statuspage-format summaries, so a failed refresh
/// during an outage reads as the vendor's problem rather than a login problem.
public enum ProviderStatusClient {
    /// Only vendors whose status page serves the Statuspage v2 API.
    static let pages: [String: URL] = [
        ClaudeProvider.vendorID: URL(string: "https://status.claude.com/api/v2/status.json")!,
        CodexProvider.vendorID: URL(string: "https://status.openai.com/api/v2/status.json")!,
    ]

    public static func fetchAll(session: URLSession = .shared) async -> [String: ProviderStatus] {
        await withTaskGroup(of: (String, ProviderStatus?).self) { group in
            for (vendor, url) in pages {
                group.addTask { (vendor, await fetch(url, session: session)) }
            }
            var result: [String: ProviderStatus] = [:]
            for await (vendor, status) in group { if let status { result[vendor] = status } }
            return result
        }
    }

    static func fetch(_ url: URL, session: URLSession) async -> ProviderStatus? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("CodeAgentMeter", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> ProviderStatus? {
        struct Body: Decodable {
            struct Status: Decodable { let indicator: String; let description: String }
            let status: Status
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let indicator = ProviderStatus.Indicator(rawValue: body.status.indicator) else { return nil }
        return ProviderStatus(indicator: indicator, description: body.status.description)
    }
}
