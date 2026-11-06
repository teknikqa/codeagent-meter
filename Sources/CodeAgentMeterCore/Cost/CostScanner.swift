import Foundation

/// Tokens and estimated cost for one (day, tool, project, model) bucket.
public struct CostBucket: Equatable, Sendable {
    public let day: Date
    public let tool: String
    public let project: String
    public let model: String
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheWrite = 0
    /// nil when the model has no known price.
    public var cost: Double?

    public var totalTokens: Int { input + output + cacheRead + cacheWrite }
}

public enum CostPeriod: String, CaseIterable, Sendable {
    case today = "Today", week = "7 days", month = "30 days"

    public func start(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today: return today
        case .week: return calendar.date(byAdding: .day, value: -6, to: today)!
        case .month: return calendar.date(byAdding: .day, value: -29, to: today)!
        }
    }
}

/// Reads the session logs Claude Code and Codex already write and prices
/// the tokens, so spend can be broken down by project and model (the quota
/// APIs only report percentages). Parsed files are cached by mtime and size.
public actor CostScanner {
    public static let lookbackDays = 30

    private struct CachedFile {
        let modified: Date
        let size: Int
        let buckets: [CostBucket]
    }

    private var cache: [String: CachedFile] = [:]
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func scan(claudeDirs: [String], codexHomes: [String], now: Date = Date()) -> [CostBucket] {
        let cutoff = calendar.date(byAdding: .day, value: -(Self.lookbackDays - 1), to: calendar.startOfDay(for: now))!
        var buckets: [CostBucket] = []
        var seen = Set<String>()
        for dir in claudeDirs {
            for file in jsonlFiles(in: (dir as NSString).appendingPathComponent("projects"), since: cutoff) where seen.insert(file.path).inserted {
                buckets += cached(file) { Self.parseClaude($0, calendar: calendar, cutoff: cutoff) }
            }
        }
        for home in codexHomes {
            for file in jsonlFiles(in: (home as NSString).appendingPathComponent("sessions"), since: cutoff) where seen.insert(file.path).inserted {
                buckets += cached(file) { Self.parseCodex($0, calendar: calendar, cutoff: cutoff) }
            }
        }
        return Self.merge(buckets)
    }

    private func cached(_ file: (path: String, modified: Date, size: Int), parse: (Data) -> [CostBucket]) -> [CostBucket] {
        if let hit = cache[file.path], hit.modified == file.modified, hit.size == file.size { return hit.buckets }
        guard let data = FileManager.default.contents(atPath: file.path) else { return [] }
        let buckets = parse(data)
        cache[file.path] = CachedFile(modified: file.modified, size: file.size, buckets: buckets)
        return buckets
    }

    private func jsonlFiles(in root: String, since cutoff: Date) -> [(path: String, modified: Date, size: Int)] {
        guard let walker = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return [] }
        var files: [(String, Date, Int)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if let modified = values?.contentModificationDate, modified >= cutoff {
                files.append((url.path, modified, values?.fileSize ?? 0))
            }
        }
        return files
    }

    // MARK: Parsing

    static func parseClaude(_ data: Data, calendar: Calendar, cutoff: Date) -> [CostBucket] {
        var buckets: [String: CostBucket] = [:]
        var seen = Set<String>()
        forEachLine(in: data, containing: "\"usage\"") { object in
            guard object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let model = message["model"] as? String, model.hasPrefix("claude-"),
                  let usage = message["usage"] as? [String: Any],
                  let day = day(of: object["timestamp"], calendar: calendar), day >= cutoff else { return }
            // Streaming writes the same message more than once.
            if let id = message["id"] as? String, !seen.insert(id + ((object["requestId"] as? String) ?? "")).inserted { return }
            let project = ((object["cwd"] as? String).map { ($0 as NSString).lastPathComponent }) ?? "unknown"
            add(&buckets, day: day, tool: "Claude Code", project: project, model: model,
                input: usage["input_tokens"] as? Int ?? 0, output: usage["output_tokens"] as? Int ?? 0,
                cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0, cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0)
        }
        return Array(buckets.values)
    }

    static func parseCodex(_ data: Data, calendar: Calendar, cutoff: Date) -> [CostBucket] {
        var buckets: [String: CostBucket] = [:]
        var model = "unknown"
        var project = "unknown"
        var previousTotal = 0
        forEachLine(in: data, containing: "\"") { object in
            guard let payload = object["payload"] as? [String: Any] else { return }
            switch object["type"] as? String {
            case "turn_context":
                model = payload["model"] as? String ?? model
                project = (payload["cwd"] as? String).map { ($0 as NSString).lastPathComponent } ?? project
            case "event_msg" where payload["type"] as? String == "token_count":
                guard let info = payload["info"] as? [String: Any],
                      let total = info["total_token_usage"] as? [String: Any],
                      let last = info["last_token_usage"] as? [String: Any],
                      let day = day(of: object["timestamp"], calendar: calendar), day >= cutoff else { return }
                // Codex repeats token_count events; only a grown running total is new usage.
                let running = total["total_tokens"] as? Int ?? 0
                guard running > previousTotal else { return }
                previousTotal = running
                let cached = last["cached_input_tokens"] as? Int ?? 0
                // OpenAI counts cached tokens inside input_tokens; split them out.
                add(&buckets, day: day, tool: "Codex", project: project, model: model,
                    input: max((last["input_tokens"] as? Int ?? 0) - cached, 0), output: last["output_tokens"] as? Int ?? 0,
                    cacheRead: cached, cacheWrite: 0)
            default: break
            }
        }
        return Array(buckets.values)
    }

    private static func forEachLine(in data: Data, containing needle: String, _ body: ([String: Any]) -> Void) {
        let needle = Data(needle.utf8)
        for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: needle) != nil {
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { body(object) }
        }
    }

    private static func day(of timestamp: Any?, calendar: Calendar) -> Date? {
        guard let string = timestamp as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string) else { return nil }
        return calendar.startOfDay(for: date)
    }

    private static func add(
        _ buckets: inout [String: CostBucket], day: Date, tool: String, project: String, model: String,
        input: Int, output: Int, cacheRead: Int, cacheWrite: Int
    ) {
        let key = "\(day.timeIntervalSince1970)|\(tool)|\(project)|\(model)"
        var bucket = buckets[key] ?? CostBucket(day: day, tool: tool, project: project, model: model)
        bucket.input += input
        bucket.output += output
        bucket.cacheRead += cacheRead
        bucket.cacheWrite += cacheWrite
        buckets[key] = bucket
    }

    /// Merges per-file buckets, then prices the totals once per bucket.
    static func merge(_ buckets: [CostBucket]) -> [CostBucket] {
        var merged: [String: CostBucket] = [:]
        for b in buckets {
            add(&merged, day: b.day, tool: b.tool, project: b.project, model: b.model,
                input: b.input, output: b.output, cacheRead: b.cacheRead, cacheWrite: b.cacheWrite)
        }
        return merged.values.map { bucket in
            var priced = bucket
            priced.cost = ModelPricing.price(for: bucket.model)?.cost(
                input: bucket.input, output: bucket.output, cacheRead: bucket.cacheRead, cacheWrite: bucket.cacheWrite)
            return priced
        }
    }
}
