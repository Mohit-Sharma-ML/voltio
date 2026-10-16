import Foundation
@testable import Voltio
import Testing

/// Budget-aware widget reload gating (WidgetSnapshotWriter's static decision
/// logic). The 2026-10-17 staleness bug: reloads were requested every 5 s tick,
/// exhausting WidgetKit's daily budget minutes after launch — widgets then fell
/// back to their own timeline cadence and lagged the menu bar by 15+ points.
struct WidgetReloadThrottleTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "test.reload.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func firstEverPublishReloads() {
        let defaults = makeDefaults()
        #expect(WidgetSnapshotWriter.shouldReload(now: Date(), defaults: defaults))
    }

    @Test func nilDefaultsNeverReloads() {
        #expect(!WidgetSnapshotWriter.shouldReload(now: Date(), defaults: nil))
    }

    @Test func reloadWithinIntervalIsSuppressed() {
        let defaults = makeDefaults()
        let now = Date()
        WidgetSnapshotWriter.recordReload(now: now, defaults: defaults)
        let fiveMinutesLater = now.addingTimeInterval(5 * 60)
        #expect(!WidgetSnapshotWriter.shouldReload(now: fiveMinutesLater, defaults: defaults))
    }

    @Test func reloadAfterIntervalIsAllowed() {
        let defaults = makeDefaults()
        let now = Date()
        WidgetSnapshotWriter.recordReload(now: now, defaults: defaults)
        let elevenMinutesLater = now.addingTimeInterval(11 * 60)
        #expect(WidgetSnapshotWriter.shouldReload(now: elevenMinutesLater, defaults: defaults))
    }

    @Test func exactlyAtIntervalBoundaryReloads() {
        let defaults = makeDefaults()
        let now = Date()
        WidgetSnapshotWriter.recordReload(now: now, defaults: defaults)
        let boundary = now.addingTimeInterval(WidgetSnapshotWriter.minimumReloadInterval)
        #expect(WidgetSnapshotWriter.shouldReload(now: boundary, defaults: defaults))
    }
}
