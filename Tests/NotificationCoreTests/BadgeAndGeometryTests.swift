import Testing
import Foundation
import CoreGraphics
@testable import NotificationCore

struct BadgeAndGeometryTests {
    @Test func testBadgeLabelsClassifyWithoutTreatingUnknownAsZero() {
        for value: String? in [nil, "", "  ", "0", "0,000"] { #expect(BadgeRecord.classify(value).status == .zero) }
        for value in ["1", "1,000", "99+"] { #expect(BadgeRecord.classify(value) == BadgeRecord(.count, value: value)) }
        for value in ["•", "!", "new messages"] { #expect(BadgeRecord.classify(value).status == .symbol) }
        #expect(BadgeRecord.classify("\n1\r").value == "1")
        #expect(BadgeRecord.classify(String(repeating: "x", count: 100)).value.count == 32)
    }
    @Test func testMatchingAvoidsConfusingOtherAppsWithWorks() {
        #expect(MessengerApp.matching(name: "Slack") == .slack)
        #expect(MessengerApp.matching(name: "line") == .line)
        #expect(MessengerApp.matching(name: "NAVER WORKS") == .works)
        #expect(MessengerApp.matching(name: "SolidWorks") == nil)
        #expect(MessengerApp.matching(name: "Slack Helper") == nil)
    }
    @Test func testAdaptivePollingCapsResetsAndRetriesErrorsPromptly() {
        var schedule = PollingSchedule(baseInterval: 1)
        let zero = BadgeSnapshot.uniform(.zero, now: 100).apps
        var intervals: [Double] = []
        for _ in 0..<40 { intervals.append(schedule.next(after: zero)) }
        #expect(Array(intervals[0...5]) == [1, 1, 1, 1, 1, 2]); #expect(intervals.max() == 10)
        #expect(schedule.next(after: BadgeSnapshot.uniform(.symbol).apps) == 1)
        for _ in 0..<40 { #expect(schedule.next(after: BadgeSnapshot.uniform(.permission).apps) == 1) }
        var fixed = PollingSchedule(baseInterval: 0.3, adaptive: false)
        for _ in 0..<40 { #expect(fixed.next(after: zero) == 0.3) }
    }
    @Test func testScreenEdgesNegativeCoordinatesAndAllSizes() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: -200, width: 1920, height: 1080), CGRect(x: 0, y: 900, width: 1200, height: 800)]
        for screen in screens {
            for size in [72.0, 96.0, 120.0] {
                for x in [screen.minX, screen.midX, screen.maxX - 1] {
                    for y in [screen.minY, screen.midY, screen.maxY - 1] {
                        let target = FollowGeometry.target(mouse: CGPoint(x: x, y: y), size: CGSize(width: size, height: size), screen: screen)
                        #expect(screen.contains(CGRect(origin: target, size: CGSize(width: size, height: size))))
                    }
                }
            }
        }
    }
    @Test func testFollowingConvergesWithoutOvershootOnDelayedOrNegativeFrames() {
        let from = CGPoint(x: -300, y: 100), target = CGPoint(x: 700, y: -400)
        var point = from
        for _ in 0..<120 { point = FollowGeometry.step(from: point, to: target, dt: 1 / 60) }
        #expect(hypot(point.x - target.x, point.y - target.y) < 0.01)
        let delayed = FollowGeometry.step(from: from, to: target, dt: 90)
        #expect(delayed.x > from.x); #expect(delayed.x < target.x)
        #expect(FollowGeometry.step(from: from, to: target, dt: -1) == from)
    }
}
