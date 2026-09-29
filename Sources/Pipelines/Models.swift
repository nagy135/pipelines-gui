import Foundation

struct Commit: Codable, Sendable {
    var title: String = ""
    var authorName: String = ""
}

struct Pipeline: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var iid: Int = 0
    var status: String = ""
    var ref: String = ""
    var sha: String = ""
    var source: String = ""
    var updatedAt: String = ""
    var createdAt: String = ""
    var startedAt: String = ""
    var duration: Double?
    var webUrl: String = ""
    var commit: Commit = Commit()
    var commitTitle: String?
    var workflowPath: String?

    var title: String { commitTitle.flatMap { $0.isEmpty ? nil : $0 } ?? commit.title }
    var shortSHA: String { String(sha.prefix(8)) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Job: Codable, Identifiable, Sendable {
    var id: Int64
    var name: String = ""
    var status: String = ""
    var stage: String = ""
    var ref: String = ""
    var webUrl: String = ""
    var createdAt: String = ""
    var startedAt: String = ""
    var finishedAt: String = ""
    var duration: Double?
    var allowFailure: Bool = false
    var retried: Bool = false
    var pipeline: Pipeline
}

struct JobRow: Codable, Identifiable, Sendable {
    var current: Job
    var previous: Job?
    var logTarget: Job
    var status: String
    var typicalDuration: Double
    var id: Int64 { current.id }
}

struct BridgeRequest: Encodable, Sendable {
    var operation: String
    var provider: String
    var repo: String
    var status: String = "active"
    var limit: Int = 10
    var pipeline: Pipeline?
    var job: Job?
}

struct BridgeResponse: Decodable, Sendable {
    var provider: String
    var pipelines: [Pipeline]?
    var pipeline: Pipeline?
    var jobs: [JobRow]?
    var text: String?
    var error: String?
}

enum Display {
    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let s = Int(min(seconds, Double(Int.max / 2)))
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m \(s % 60)s" }
        if s >= 60 { return "\(s / 60)m \(s % 60)s" }
        return "\(s)s"
    }

    static func elapsed(_ startedAt: String, duration: Double?, status: String, now: Date) -> Double? {
        if status == "running", let start = date(startedAt) { return max(0, now.timeIntervalSince(start)) }
        return duration
    }

    static func relative(_ value: String, now: Date = Date()) -> String {
        guard let date = date(value) else { return "—" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m ago" }
        return "\(seconds / 86400)d ago"
    }

    static func fullDate(_ value: String) -> String {
        date(value)?.formatted(date: .abbreviated, time: .standard) ?? "—"
    }
}
