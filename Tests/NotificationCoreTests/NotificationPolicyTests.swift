import Testing
import Foundation
@testable import NotificationCore

struct NotificationPolicyTests {
    private func snapshot(_ slack: BadgeRecord = BadgeRecord(.zero), line: BadgeRecord = BadgeRecord(.zero), at time: Double = 100) -> BadgeSnapshot {
        BadgeSnapshot(updatedAt: time, apps: [.slack: slack, .line: line, .works: BadgeRecord(.zero)])
    }
    @Test func testAllModesStartQuietAndShowOnBadge() {
        for mode in AlertMode.allCases {
            var policy = NotificationPolicy(mode: mode)
            policy.update(nil, now: 100); #expect(!(policy.visible))
            policy.update(snapshot(), now: 100); #expect(!(policy.visible))
            policy.update(snapshot(BadgeRecord(.count, value: "1")), now: 100)
            #expect(policy.visible); #expect(policy.displayedApps == [.slack])
        }
    }
    @Test func testUnreadHidesOnlyWhenAllBadgesClear() {
        var policy = NotificationPolicy()
        policy.update(snapshot(BadgeRecord(.count, value: "2"), line: BadgeRecord(.symbol)), now: 100)
        policy.update(snapshot(line: BadgeRecord(.symbol), at: 101), now: 101)
        #expect(policy.visible); #expect(policy.displayedApps == [.line])
        policy.update(snapshot(at: 102), now: 102); #expect(!(policy.visible))
    }
    @Test func testTimedExpiryIsNotExtendedByHeartbeatOrReadingSomeMessages() {
        var policy = NotificationPolicy(mode: .timed)
        policy.update(snapshot(BadgeRecord(.count, value: "4")), now: 100)
        policy.update(snapshot(BadgeRecord(.count, value: "3"), at: 109), now: 109); #expect(policy.visible)
        policy.update(snapshot(BadgeRecord(.count, value: "3"), at: 110), now: 110); #expect(!(policy.visible))
    }
    @Test func testIncreasingCountAndAnotherAppRestartTimedAlert() {
        var policy = NotificationPolicy(mode: .timed)
        policy.update(snapshot(BadgeRecord(.count, value: "1")), now: 100)
        policy.update(snapshot(BadgeRecord(.count, value: "2"), at: 109), now: 109)
        policy.update(snapshot(BadgeRecord(.count, value: "2"), at: 111), now: 111); #expect(policy.visible)
        policy.update(snapshot(BadgeRecord(.count, value: "2"), line: BadgeRecord(.symbol), at: 118), now: 118)
        policy.update(snapshot(at: 120), now: 120); #expect(policy.visible)
        policy.update(snapshot(at: 128), now: 128); #expect(!(policy.visible))
    }
    @Test func testManualPersistsUntilDismissedEvenAfterReadOrDataLoss() {
        var policy = NotificationPolicy(mode: .manual)
        policy.update(snapshot(BadgeRecord(.symbol)), now: 100)
        policy.update(snapshot(at: 101), now: 101); #expect(policy.visible)
        policy.update(nil, now: 200); #expect(policy.visible)
        policy.dismiss(); #expect(!(policy.visible))
    }
    @Test func testDismissedAlertDoesNotReturnUntilNewEvent() {
        for mode in AlertMode.allCases {
            var policy = NotificationPolicy(mode: mode)
            policy.update(snapshot(BadgeRecord(.count, value: "2")), now: 100); policy.dismiss()
            policy.update(snapshot(BadgeRecord(.count, value: "2"), at: 101), now: 101); #expect(!(policy.visible))
            policy.update(snapshot(BadgeRecord(.count, value: "1"), at: 102), now: 102); #expect(!(policy.visible))
            policy.update(snapshot(BadgeRecord(.count, value: "3"), at: 103), now: 103); #expect(policy.visible)
        }
    }
    @Test func testPermissionAndQueryRecoveryDoNotInventArrival() {
        var policy = NotificationPolicy(mode: .timed)
        policy.update(snapshot(BadgeRecord(.count, value: "1")), now: 100)
        policy.update(snapshot(BadgeRecord(.query), at: 105), now: 105)
        policy.update(snapshot(BadgeRecord(.permission), at: 108), now: 108)
        policy.update(snapshot(BadgeRecord(.count, value: "1"), at: 111), now: 111); #expect(!(policy.visible))
    }
    @Test func testModeSwitchUsesCurrentUnreadState() {
        var policy = NotificationPolicy(mode: .manual)
        policy.update(snapshot(BadgeRecord(.count, value: "1")), now: 100)
        policy.select(.unread, snapshot: snapshot(at: 101), now: 101); #expect(!(policy.visible))
        policy.select(.timed, snapshot: snapshot(BadgeRecord(.symbol), at: 102), now: 102); #expect(policy.visible)
    }
    @Test func testUnreadRejectsStaleFutureAndIncompleteSamples() {
        var policy = NotificationPolicy()
        let unread = snapshot(BadgeRecord(.count, value: "1"))
        policy.update(unread, now: 126); #expect(!(policy.visible))
        policy.update(unread, now: 90); #expect(!(policy.visible))
        let incomplete = BadgeSnapshot(updatedAt: 100, apps: [.slack: BadgeRecord(.count, value: "1")])
        policy.update(incomplete, now: 100); #expect(!(policy.visible))
        policy.update(unread, now: 100); #expect(policy.visible)
    }
}
