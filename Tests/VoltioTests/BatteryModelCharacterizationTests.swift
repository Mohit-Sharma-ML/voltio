import Foundation
import XCTest
import PowerCore
@testable import Voltio

/// Characterization tests for `BatteryModel`'s decision logic — the untested
/// conductor where both 2026-10-16 launch crashes lived. These pin CURRENT
/// behavior (Phase 0 of Docs/hardening-plan.md) so later refactors are safe.
///
/// The model is constructed with `startMonitors: false` — no poll tasks, no
/// IOKit/BT/WidgetKit. Tests drive ticks by calling `refreshBattery()`
/// directly and observe effects through the fakes.
@MainActor
final class BatteryModelCharacterizationTests: XCTestCase {

    private var settings: AppSettings!
    private var provider: FakeBatteryProvider!
    private var widgetPublisher: FakeWidgetPublisher!
    private var chargeLimitReader: FakeChargeLimitReader!
    private var model: BatteryModel!

    override func setUp() {
        super.setUp()
        settings = AppSettings()
        provider = FakeBatteryProvider(states: [ModelTestSnapshots.make(percentage: 80)])
        widgetPublisher = FakeWidgetPublisher()
        chargeLimitReader = FakeChargeLimitReader()
        model = BatteryModel(
            settings: settings,
            reader: provider,
            widgetWriter: widgetPublisher,
            chargeLimitReader: chargeLimitReader,
            startMonitors: false
        )
    }

    override func tearDown() {
        model = nil
        settings = nil
        provider = nil
        widgetPublisher = nil
        chargeLimitReader = nil
        super.tearDown()
    }

    // MARK: - Publish behavior

    func testFirstTickPublishesSnapshot() {
        model.refreshBattery()
        XCTAssertEqual(widgetPublisher.publishCount, 1)
        XCTAssertEqual(widgetPublisher.calls.first?.percentage, 80)
    }

    func testUnchangedSnapshotStillPublishesEachTick() {
        // The MENU BAR gates re-rasterization; the widget pipeline publishes
        // every tick (energy accounting needs samples even when unchanged).
        model.refreshBattery()
        model.refreshBattery()
        model.refreshBattery()
        XCTAssertEqual(widgetPublisher.publishCount, 3)
        // Only the first publish is a forced reload (state flip from nil).
        XCTAssertEqual(widgetPublisher.calls.first?.forceReload, true)
        XCTAssertFalse(widgetPublisher.calls.last!.forceReload)
    }

    func testStateFlipForcesReload() {
        provider = FakeBatteryProvider(states: [
            ModelTestSnapshots.make(percentage: 80, isCharging: false, isPluggedIn: false),
            ModelTestSnapshots.make(percentage: 81, isCharging: true, isPluggedIn: true),
            ModelTestSnapshots.make(percentage: 82, isCharging: true, isPluggedIn: true),
        ])
        model = BatteryModel(
            settings: settings,
            reader: provider,
            widgetWriter: widgetPublisher,
            chargeLimitReader: chargeLimitReader,
            startMonitors: false
        )

        model.refreshBattery() // initial: on battery
        widgetPublisher.reset()

        provider.advance()
        model.refreshBattery() // flip: charging begins → force reload
        XCTAssertEqual(widgetPublisher.calls.count, 1)
        XCTAssertTrue(widgetPublisher.calls[0].forceReload)

        provider.advance()
        model.refreshBattery() // still charging, no flip → no force
        XCTAssertFalse(widgetPublisher.calls.last!.forceReload)
    }

    func testPauseHoldStateIsPublished() {
        provider = FakeBatteryProvider(states: [
            ModelTestSnapshots.make(
                percentage: 80, isCharging: false, isPluggedIn: true,
                notChargingReason: .optimizedChargingHold
            ),
        ])
        model = BatteryModel(
            settings: settings,
            reader: provider,
            widgetWriter: widgetPublisher,
            chargeLimitReader: chargeLimitReader,
            startMonitors: false
        )
        model.refreshBattery()
        XCTAssertEqual(widgetPublisher.calls.first?.isChargeHold, true)
    }

    // MARK: - Charge limit

    func testChargeLimitPublishedOnChangeOnly() {
        // The model deliberately reads charge-limit off-main (serial IO queue
        // + MainActor hop — pmset inline on the tick crashed IOPS callbacks,
        // see refreshChargeLimit doc comment), so the update lands
        // asynchronously. Run the tick's async tail before asserting.
        chargeLimitReader.set(ChargeLimitState(percent: nil))
        model.refreshBattery()
        let drain = { @MainActor in RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }
        drain()

        chargeLimitReader.set(ChargeLimitState(percent: 80))
        model.refreshBattery()
        drain()
        XCTAssertEqual(model.chargeLimit?.percent, 80)

        // Same value again → stays, no churn (publish-on-change contract).
        model.refreshBattery()
        drain()
        XCTAssertEqual(model.chargeLimit?.percent, 80)
    }

    // MARK: - Display gating

    func testSnapshotOnlyRepublishedOnIOPSErrorFreeTicks() {
        // The model's lastError stays nil on successful reads; lastUpdated
        // advances every tick even when the snapshot is unchanged.
        model.refreshBattery()
        let first = model.lastUpdated
        model.refreshBattery()
        XCTAssertNotNil(model.lastUpdated)
        XCTAssertGreaterThanOrEqual(model.lastUpdated!, first!)
        XCTAssertNil(model.lastError)
    }

    func testFakeBatteryPercentOverridesDisplay() {
        settings.fakeBatteryPercent = 42
        XCTAssertEqual(model.snapshot?.percentage, 42)
    }

    // MARK: - Energy recording

    func testEnergySamplesAccumulate() {
        // Two distinct watt readings → EnergyStore has a today total.
        provider = FakeBatteryProvider(states: [
            ModelTestSnapshots.make(percentage: 80, isPluggedIn: false),
            ModelTestSnapshots.make(percentage: 79, isPluggedIn: false),
        ])
        model = BatteryModel(
            settings: settings,
            reader: provider,
            widgetWriter: widgetPublisher,
            chargeLimitReader: chargeLimitReader,
            startMonitors: false
        )
        model.refreshBattery()
        provider.advance()
        model.refreshBattery()
        XCTAssertNotNil(model.todayEnergy)
        XCTAssertNotNil(model.smoothedPowerWatts)
    }
}
