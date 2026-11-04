import Foundation

public enum MessengerApp: String, CaseIterable, Codable, Hashable {
    case slack = "Slack", line = "LINE", works = "WORKS"
    public var bundleIdentifier: String {
        switch self {
        case .slack: return "com.tinyspeck.slackmacgap"
        case .line: return "jp.naver.line.mac"
        case .works: return "com.naver.naverworks"
        }
    }
    public static func matching(name: String) -> MessengerApp? {
        switch name.lowercased() {
        case "slack": return .slack
        case "line": return .line
        case "works", "naver works", "네이버웍스", "네이버 웍스": return .works
        default: return nil
        }
    }
}

public enum BadgeStatus: String, Codable {
    case count, zero, symbol, missing, permission, disabled, starting, query
}

public struct BadgeRecord: Codable, Equatable {
    public let status: BadgeStatus
    public let value: String
    public init(_ status: BadgeStatus, value: String = "") { self.status = status; self.value = value }
    public var hasBadge: Bool { status == .count || status == .symbol }
    public var number: UInt64? { UInt64(value.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "+", with: "")) }
    public func arrived(after previous: BadgeRecord?) -> Bool {
        guard hasBadge else { return false }
        guard let previous, previous.hasBadge else { return true }
        if let number, let oldNumber = previous.number { return number > oldNumber }
        return false
    }
    public static func classify(_ label: String?) -> BadgeRecord {
        let cleaned = String((label ?? "").unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return BadgeRecord(.zero) }
        let digits = cleaned.replacingOccurrences(of: ",", with: "")
        if !digits.isEmpty && digits.allSatisfy({ $0 == "0" }) { return BadgeRecord(.zero) }
        if cleaned.range(of: "^[0-9][0-9,]*\\+?$", options: .regularExpression) != nil {
            return BadgeRecord(.count, value: String(cleaned.prefix(32)))
        }
        return BadgeRecord(.symbol, value: String(cleaned.prefix(32)))
    }
}

public struct BadgeSnapshot: Codable {
    public let updatedAt: TimeInterval
    public let pollInterval: TimeInterval
    public let apps: [MessengerApp: BadgeRecord]
    public init(updatedAt: TimeInterval, pollInterval: TimeInterval = 1, apps: [MessengerApp: BadgeRecord]) {
        self.updatedAt = updatedAt; self.pollInterval = pollInterval; self.apps = apps
    }
    public var activeApps: [MessengerApp] { MessengerApp.allCases.filter { apps[$0]?.hasBadge == true } }
    public func isFresh(at now: TimeInterval) -> Bool {
        updatedAt.isFinite && now.isFinite && pollInterval.isFinite && pollInterval > 0 && pollInterval <= 10
            && now - updatedAt >= -5 && now - updatedAt <= 25
            && MessengerApp.allCases.allSatisfy { apps[$0] != nil }
    }
    public static func uniform(_ status: BadgeStatus, now: TimeInterval = Date().timeIntervalSince1970) -> BadgeSnapshot {
        BadgeSnapshot(updatedAt: now, apps: Dictionary(uniqueKeysWithValues: MessengerApp.allCases.map { ($0, BadgeRecord(status)) }))
    }
}

public struct PollingSchedule {
    public var baseInterval: TimeInterval
    public var adaptive: Bool
    private var last: [MessengerApp: BadgeRecord] = [:]
    private var unchanged = 0
    public init(baseInterval: TimeInterval = 1, adaptive: Bool = true) {
        self.baseInterval = max(0.3, min(5, baseInterval)); self.adaptive = adaptive
    }
    public mutating func next(after apps: [MessengerApp: BadgeRecord]) -> TimeInterval {
        let failed = apps.values.contains { [.permission, .query, .starting].contains($0.status) }
        unchanged = apps == last && !failed ? min(unchanged + 1, 30) : 0
        last = apps
        return adaptive && !failed ? min(10, baseInterval * pow(2, Double(unchanged / 5))) : baseInterval
    }
}
