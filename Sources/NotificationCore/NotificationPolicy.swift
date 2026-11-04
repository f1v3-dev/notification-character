import Foundation

public enum AlertMode: String, CaseIterable {
    case unread, timed, manual
    public var title: String {
        switch self {
        case .unread: return "알림을 읽을 때까지"
        case .timed: return "10초 동안만"
        case .manual: return "직접 닫을 때까지"
        }
    }
}

public struct NotificationPolicy {
    public private(set) var mode: AlertMode
    public private(set) var activeApps: [MessengerApp] = []
    public private(set) var visible = false
    private var previous: [MessengerApp: BadgeRecord] = [:]
    private var latchedApps: [MessengerApp] = []
    private var latched = false
    private var dismissed = false
    private var deadline: TimeInterval = 0
    public init(mode: AlertMode = .unread) { self.mode = mode }

    public mutating func update(_ snapshot: BadgeSnapshot?, now: TimeInterval) {
        let fresh = snapshot.flatMap { $0.isFresh(at: now) ? $0 : nil }
        activeApps = fresh?.activeApps ?? []
        if let fresh {
            let arrivals = MessengerApp.allCases.filter { fresh.apps[$0]?.arrived(after: previous[$0]) == true }
            if !arrivals.isEmpty {
                latched = true; dismissed = false; deadline = now + 10; latchedApps = activeApps
            }
            for (app, record) in fresh.apps where ![.query, .permission, .starting].contains(record.status) {
                previous[app] = record
            }
        }
        switch mode {
        case .unread: visible = !dismissed && !activeApps.isEmpty
        case .timed: visible = latched && now < deadline
        case .manual: visible = latched
        }
    }
    public mutating func dismiss() { latched = false; dismissed = true; visible = false }
    public mutating func select(_ mode: AlertMode, snapshot: BadgeSnapshot?, now: TimeInterval) {
        self.mode = mode; dismissed = false; latched = false
        if let snapshot, snapshot.isFresh(at: now), !snapshot.activeApps.isEmpty {
            latched = true; latchedApps = snapshot.activeApps; deadline = now + 10
        }
        update(snapshot, now: now)
    }
    public var displayedApps: [MessengerApp] { mode == .unread ? activeApps : latchedApps }
}
