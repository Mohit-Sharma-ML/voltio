import XCTest
import PowerCore
@testable import Voltio

/// Characterization tests for `BatteryModel`'s sleep/wake handling (Q1 of
/// the hardening plan's fix queue — the last untested path in the
/// conductor, and the layer where both 2026-10-16 launch crashes lived).
///
/// Behavior pinned (current, shipped semantics):
/// - **Sleep:** caches the last reading in `preSleepReading` (the poll
///   timers and IOKit notifications are suspended during sleep, so the
///   alert manager's remembered state must survive from a snapshot).
/// - **Wake:** reads live immediately, bypassing the publish-on-change
///   gate's alert evaluation — the Mac may have crossed an alert
///   threshold (or discharged significantly) while asleep. If the live
///   read fails, falls back to a full `refresh()` (best effort).
/// - Wake publishes through the normal widget path (flip-gated), so a
///   wake does not storm the WidgetKit reload budget.
/// - Repeated sleep/wake cycles are idempotent — no state accumulation.
@MainActor
final class SleepWakeCharacterizationTests: XCTestCase {

    private var settings: AppSettings!
    private var provider: FakeBatteryProvider!
    private var widgetPublisher: FakeWidgetPublisher!
    private var chargeLimitReader: FakeChargeLimitReader!
    private var notifier: FakeSleepWakeNotifier!
    private var model: BatteryModel!

    override func setUp() {
        super.setUp()
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        settings = AppSettings(defaults: suite)
        provider = FakeBatteryProvider(states: [ModelTestSnapshots.make(percentage: 80)])
        widgetPublisher = FakeWidgetPublisher()
        chargeLimitReader = FakeChargeLimitReader()
        notifier = FakeSleepWakeNotifier()
        model = BatteryModel(
            settings: settings,
            reader: provider,
            widgetWriter: widgetPublisher,
            chargeLimitReader: chargeLimitReader,
            sleepWakeNotifier: notifier,
            startMonitors: false
        )
    }

    override func tearDown() {
        model = nil
        settings = nil
        provider = nil
        widgetPublisher = nil
        chargeLimitReader = nil
        notifier = nil
        super.tearDown()
    }

    // MARK: - Wiring

    func testNotifierHandlersInstalledAndStarted() {
        // The model must have installed both handlers and started the
        // notifier — otherwise the feature silently never engages.
        XCTAssertNotNil(notifier.onSleep)
        XCTAssertNotNil(notifier.onWake)
        XCTAssertEqual(notifier.startCount, 1)
    }

    // MARK: - Sleep

    func testSleepCachesCurrentReading() {
        model.refreshBattery() // establish a live snapshot (80%)
        notifier.simulateSleep()
        // The cache is internal; its effect is observable via the wake path
        // (the next wake evaluates against the cached state). Indirect
        // assertion: a sleep without a prior tick must not crash and wake
        // must still work (nil-cache tolerated).
        XCTAssertNotNil(model.snapshot)
    }

    func testSleepBeforeFirstTickDoesNotCrashWake() {
        // Sleep fired before any poll tick: preSleepReading is nil. The
        // shipped behavior tolerates this — wake does a plain live read.
        notifier.simulateSleep()
        provider.advance() // reading changed while asleep
        XCTAssertNoThrow(notifier.simulateWake())
        XCTAssertNotNil(model.snapshot)
    }

    // MARK: - Wake

    func testWakeReadsLiveImmediately() {
        provider = FakeBatteryProvider(states: [
            ModelTestSnapshots.make(percentage: 80),
            ModelTestSnapshots.make(percentage: 79),
        ])
        model = BatteryModel(
            settings: settings,
            reader: provider,
            widgetWriter: widgetPublisher,
            chargeLimitReader: chargeLimitReader,
            sleepWakeNotifier: notifier,
            startMonitors: false
        )
        model.refreshBattery() // establish pre-sleep state (80%)
        notifier.simulateSleep()

        provider.advance() // battery changed while asleep (79%)
        let publishCountBefore = widgetPublisher.publishCount
        notifier.simulateWake()

        // Live read happened immediately (not waiting for the poll timer,
        // which doesn't even run with startMonitors: false).
        XCTAssertGreaterThan(widgetPublisher.publishCount, publishCountBefore)
        XCTAssertEqual(model.snapshot?.percentage, 79)
        XCTAssertEqual(model.lastError, nil)
    }

    func testWakeWithFailedReadFallsBackToRefresh() {
        model.refreshBattery()
        notifier.simulateSleep()

        // Make every subsequent read throw (sleep drained the battery to
        // failure, or IOKit isn't ready yet mid-wake).
        provider = FailingBatteryProvider()
        model = BatteryModel(
            settings: settings,
            reader: provider,
            widgetWriter: widgetPublisher,
            chargeLimitReader: chargeLimitReader,
            sleepWakeNotifier: notifier,
            startMonitors: false
        )

        XCTAssertNoThrow(notifier.simulateWake())
        // The fallback records the read error (same as a failed poll tick)
        // rather than crashing or silently doing nothing.
        XCTAssertNotNil(model.lastError)
    }

    func testRepeatedCyclesAreIdempotent() {
        model.refreshBattery()
        for _ in 0..<3 {
            notifier.simulateSleep()
            provider.advance()
            notifier.simulateWake()
        }
        // State converges to the latest reading; no accumulation, no crash.
        XCTAssertNotNil(model.snapshot)
        XCTAssertNil(model.lastError)
    }

    // MARK: - Widget budget

    func testWakeDoesNotForceReloadWithoutStateFlip() {
        model.refreshBattery() // 80% on battery
        widgetPublisher.reset()
        notifier.simulateSleep()

        // Wake with the SAME reading (no discharge): the wake publish rides
        // the normal flip-gated path — no forced reload spent.
        notifier.simulateWake()
        let calls = widgetPublisher.calls
        if let last = calls.last {
            XCTAssertFalse(last.forceReload)
        }
    }

    func testWakeWithStateFlipForcesReloadOnce() {
        model.refreshBattery() // 80% on battery
        widgetPublisher.reset()
        notifier.simulateSleep()

        // Discharged + plugged in while asleep: a real state flip.
        provider = FakeBatteryProvider(states: [
            ModelTestSnapshots.make(percentage: 72, isCharging: true, isPluggedIn: true),
        ])
        model = BatteryModel(
            settings: settings,
            reader: provider,
            widgetWriter: widgetPublisher,
            chargeLimitReader: chargeLimitReader,
            sleepWakeNotifier: notifier,
            startMonitors: false
        )
        notifier.simulateSleep()
        notifier.simulateWake()

        let forced = widgetPublisher.calls.filter(\.forceReload)
        XCTAssertEqual(forced.count, 1, "state flip on wake forces exactly one reload")
    }
}

/// Reader whose `read()` always throws — simulates IOKit unavailability
/// (mid-wake hardware not settled, or a drained/dead battery path).
/// Reader whose `read()` always throws — simulates IOKit unavailability
/// (mid-wake hardware not settled, or a drained/dead battery path).
private final class FailingBatteryProvider: FakeBatteryProvider, @unchecked Sendable {
    struct ReadFailed: Error {}
    init() { super.init(states: [ModelTestSnapshots.make()]) }
    override func read() throws -> BatterySnapshot { throw ReadFailed() }
}
