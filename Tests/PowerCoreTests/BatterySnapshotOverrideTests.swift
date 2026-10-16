import XCTest
@testable import PowerCore

final class BatterySnapshotOverrideTests: XCTestCase {

    private func snapshot(percentage: Int) -> BatterySnapshot {
        BatterySnapshot(
            percentage: percentage,
            isCharging: false,
            isPluggedIn: true,
            isFullyCharged: false,
            isLowPowerMode: true,
            minutesRemaining: 42,
            cycleCount: 139,
            designCycleCount: 1000,
            temperatureCelsius: 30.5,
            voltage: 12.912,
            amperage: -54,
            currentCapacitymAh: 8158,
            maxCapacitymAh: 8481,
            designCapacitymAh: 8579,
            adapterWatts: 35,
            adapterName: "35W USB-C Power Adapter",
            systemPowerWatts: 32.7,
            batteryPowerWatts: -6.97,
            notChargingReason: .optimizedChargingHold,
            serialNumber: "F9D1234",
            manufactureDate: nil
        )
    }

    func testOverrideReplacesPercentageOnly() {
        let original = snapshot(percentage: 97)
        let overridden = original.overridingPercentage(13)

        XCTAssertEqual(overridden.percentage, 13)
        // Every other field carries over unchanged.
        XCTAssertEqual(overridden.isCharging, original.isCharging)
        XCTAssertEqual(overridden.isPluggedIn, original.isPluggedIn)
        XCTAssertEqual(overridden.isFullyCharged, original.isFullyCharged)
        XCTAssertEqual(overridden.isLowPowerMode, original.isLowPowerMode)
        XCTAssertEqual(overridden.minutesRemaining, original.minutesRemaining)
        XCTAssertEqual(overridden.cycleCount, original.cycleCount)
        XCTAssertEqual(overridden.designCycleCount, original.designCycleCount)
        XCTAssertEqual(overridden.temperatureCelsius, original.temperatureCelsius)
        XCTAssertEqual(overridden.voltage, original.voltage)
        XCTAssertEqual(overridden.amperage, original.amperage)
        XCTAssertEqual(overridden.currentCapacitymAh, original.currentCapacitymAh)
        XCTAssertEqual(overridden.maxCapacitymAh, original.maxCapacitymAh)
        XCTAssertEqual(overridden.designCapacitymAh, original.designCapacitymAh)
        XCTAssertEqual(overridden.adapterWatts, original.adapterWatts)
        XCTAssertEqual(overridden.adapterName, original.adapterName)
        XCTAssertEqual(overridden.systemPowerWatts, original.systemPowerWatts)
        XCTAssertEqual(overridden.batteryPowerWatts, original.batteryPowerWatts)
        XCTAssertEqual(overridden.notChargingReason, original.notChargingReason)
        XCTAssertEqual(overridden.serialNumber, original.serialNumber)
        XCTAssertEqual(overridden.manufactureDate, original.manufactureDate)
        // Original is untouched (value semantics).
        XCTAssertEqual(original.percentage, 97)
    }

    func testOverrideClampsOutOfRangeValues() {
        XCTAssertEqual(snapshot(percentage: 50).overridingPercentage(-5).percentage, 0)
        XCTAssertEqual(snapshot(percentage: 50).overridingPercentage(150).percentage, 100)
        XCTAssertEqual(snapshot(percentage: 50).overridingPercentage(0).percentage, 0)
        XCTAssertEqual(snapshot(percentage: 50).overridingPercentage(100).percentage, 100)
    }
}
