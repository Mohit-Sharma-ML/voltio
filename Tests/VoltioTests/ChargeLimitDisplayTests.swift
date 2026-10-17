import XCTest
import PowerCore
@testable import Voltio

/// Presentation rules for the native charge-limit awareness feature
/// (from the Gap #2 charge-limit spike).
final class ChargeLimitDisplayTests: XCTestCase {

    func testLabelShowsConfiguredLimit() throws {
        let snapshot = Self.snapshot()
        let label = snapshot.chargeLimitLabel(limit: ChargeLimitState(percent: 80))
        XCTAssertEqual(label, "macOS Charge Limit: 80%")
    }

    func testLabelNilWhenNoLimit() {
        let snapshot = Self.snapshot()
        XCTAssertNil(snapshot.chargeLimitLabel(limit: ChargeLimitState(percent: nil)))
        XCTAssertNil(snapshot.chargeLimitLabel(limit: nil))
    }

    private static func snapshot(
        percentage: Int = 80,
        isCharging: Bool = false,
        isPluggedIn: Bool = true
    ) -> BatterySnapshot {
        BatterySnapshot(
            percentage: percentage,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isFullyCharged: false,
            minutesRemaining: nil,
            cycleCount: 100,
            designCycleCount: 1000,
            temperatureCelsius: 28,
            voltage: 11.6,
            amperage: 0,
            currentCapacitymAh: 4000,
            maxCapacitymAh: 8000,
            designCapacitymAh: 8800,
            adapterWatts: 96,
            adapterName: nil,
            systemPowerWatts: nil,
            batteryPowerWatts: nil
        )
    }
}
