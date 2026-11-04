import AppKit
import ApplicationServices
import NotificationCore

/// Reads only the Dock's app tiles and badge labels. No AppleScript, shell, or System Events.
final class DockBadgeReader {
    private var identifiers: [URL: String] = [:]

    func read(enabled: Set<MessengerApp>) -> [MessengerApp: BadgeRecord] {
        var result = Dictionary(uniqueKeysWithValues: MessengerApp.allCases.map { ($0, BadgeRecord(enabled.contains($0) ? .query : .disabled)) })
        guard !enabled.isEmpty else { return result }
        guard AXIsProcessTrusted() else {
            for app in enabled { result[app] = BadgeRecord(.permission) }; return result
        }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return result }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.4)
        guard let list = findList(root), let tiles = children(of: list) else { return result }
        var matches: [MessengerApp: [AXUIElement]] = [:]
        for tile in tiles.prefix(256) {
            AXUIElementSetMessagingTimeout(tile, 0.3)
            var app: MessengerApp?
            if let rawURL = value(tile, "AXURL").value,
               let url = (rawURL as? URL) ?? (rawURL as? String).flatMap(URL.init(string:)) {
                let identifier = identifiers[url] ?? Bundle(url: url)?.bundleIdentifier
                if let identifier { identifiers[url] = identifier }
                app = MessengerApp.allCases.first { $0.bundleIdentifier == identifier }
            }
            if app == nil {
                let title = value(tile, kAXTitleAttribute).value as? String
                let description = value(tile, kAXDescriptionAttribute).value as? String
                app = [title, description].compactMap { $0 }.compactMap(MessengerApp.matching(name:)).first
            }
            if let app, enabled.contains(app) { matches[app, default: []].append(tile) }
        }
        for app in enabled {
            guard let found = matches[app], !found.isEmpty else { result[app] = BadgeRecord(.missing); continue }
            guard found.count == 1 else { result[app] = BadgeRecord(.query); continue }
            let badge = value(found[0], "AXStatusLabel")
            switch badge.error {
            case .success:
                if let label = badge.value as? String { result[app] = BadgeRecord.classify(label) }
                else if let number = badge.value as? NSNumber { result[app] = BadgeRecord.classify(number.stringValue) }
                else if badge.value == nil { result[app] = BadgeRecord(.zero) }
                else { result[app] = BadgeRecord(.query) }
            case .noValue, .attributeUnsupported: result[app] = BadgeRecord(.zero)
            case .apiDisabled: result[app] = BadgeRecord(.permission)
            default: result[app] = BadgeRecord(.query)
            }
        }
        return result
    }
    private func value(_ element: AXUIElement, _ attribute: String) -> (value: CFTypeRef?, error: AXError) {
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        return (result, error)
    }
    private func children(of element: AXUIElement) -> [AXUIElement]? {
        let result = value(element, kAXChildrenAttribute)
        guard result.error == .success else { return nil }
        return result.value as? [AXUIElement]
    }
    private func findList(_ root: AXUIElement) -> AXUIElement? {
        var level = [root]
        for _ in 0..<3 {
            var next: [AXUIElement] = []
            for element in level.prefix(64) {
                AXUIElementSetMessagingTimeout(element, 0.3)
                if value(element, kAXRoleAttribute).value as? String == kAXListRole { return element }
                next.append(contentsOf: children(of: element) ?? [])
            }
            level = next
        }
        return nil
    }
}

final class DockBadgeMonitor {
    private let queue = DispatchQueue(label: "NotificationCharacter.DockBadgeMonitor", qos: .utility)
    private let reader = DockBadgeReader()
    private var generation = 0

    func start(enabled: Set<MessengerApp>, interval: TimeInterval, adaptive: Bool, receive: @escaping (BadgeSnapshot) -> Void) {
        queue.async { [self] in
            generation += 1
            poll(generation: generation, enabled: enabled, schedule: PollingSchedule(baseInterval: interval, adaptive: adaptive), receive: receive)
        }
    }
    func stop() { queue.async { self.generation += 1 } }
    private func poll(generation expected: Int, enabled: Set<MessengerApp>, schedule: PollingSchedule, receive: @escaping (BadgeSnapshot) -> Void) {
        guard generation == expected else { return }
        let records = reader.read(enabled: enabled)
        var next = schedule
        let delay = next.next(after: records)
        let snapshot = BadgeSnapshot(updatedAt: Date().timeIntervalSince1970, pollInterval: delay, apps: records)
        DispatchQueue.main.async { receive(snapshot) }
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            poll(generation: expected, enabled: enabled, schedule: next, receive: receive)
        }
    }
}
