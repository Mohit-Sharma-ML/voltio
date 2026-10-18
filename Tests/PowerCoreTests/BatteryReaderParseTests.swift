import XCTest
@testable import PowerCore

/// Validates the parser against a fixture captured from a real
/// `ioreg -rn AppleSmartBattery` dump on an Apple Silicon MacBook.
final class BatteryReaderParseTests: XCTestCase {

    /// Real values observed on the reference machine (MacBook, 35W adapter).
    private func referenceFixture() -> [String: Any] {
        [
            "CurrentCapacity": 97,
            "IsCharging": true,
            "ExternalConnected": true,
            "FullyCharged": false,
            "AvgTimeToFull": 328,
            "AvgTimeToEmpty": 65535,
            "TimeRemaining": 328,
            "CycleCount": 139,
            "DesignCycleCount9C": 1000,
            "Temperature": 3050,
            "Voltage": 12912,
            // Stored by IOKit as an unsigned 64-bit two's-complement of -54.
            "Amperage": NSNumber(value: UInt64(18_446_744_073_709_551_562)),
            "AppleRawCurrentCapacity": 8158,
            "AppleRawMaxCapacity": 8481,
            "DesignCapacity": 8579,
            "AdapterDetails": [
                "Watts": 35,
                "Name": "35W USB-C Power Adapter ",
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 32713,
                "BatteryPower": NSNumber(value: UInt64(18_446_744_073_709_550_919)), // -697
            ],
        ]
    }

    func testParsesCoreValues() {
        let s = BatteryReader.parse(referenceFixture())

        XCTAssertEqual(s.percentage, 97)
        XCTAssertTrue(s.isCharging)
        XCTAssertTrue(s.isPluggedIn)
        XCTAssertFalse(s.isFullyCharged)
        XCTAssertEqual(s.cycleCount, 139)
        XCTAssertEqual(s.designCycleCount, 1000)
        XCTAssertEqual(s.currentCapacitymAh, 8158)
        XCTAssertEqual(s.maxCapacitymAh, 8481)
        XCTAssertEqual(s.designCapacitymAh, 8579)
        XCTAssertEqual(s.adapterWatts, 35)
        XCTAssertEqual(s.adapterName, "35W USB-C Power Adapter")
    }

    func testDerivedAndNormalizedValues() {
        let s = BatteryReader.parse(referenceFixture())

        // Health floors to 98 (8481 / 8579 = 98.85%), matching macOS tools.
        XCTAssertEqual(s.healthPercent, 98)
        // Pack charge ratio floors to 96 (8158 / 8481 = 96.19%).
        XCTAssertEqual(s.packChargePercent, 96)
        XCTAssertEqual(s.temperatureCelsius, 30.5, accuracy: 0.001)
        XCTAssertEqual(s.temperatureFahrenheit, 86.9, accuracy: 0.05)
        XCTAssertEqual(s.voltage, 12.912, accuracy: 0.0001)
        XCTAssertEqual(s.systemPowerWatts ?? 0, 32.713, accuracy: 0.0001)
    }

    func testTwosComplementCurrentIsSigned() {
        let s = BatteryReader.parse(referenceFixture())
        XCTAssertEqual(s.amperage, -54)
        XCTAssertEqual(s.batteryPowerWatts ?? 0, -0.697, accuracy: 0.0001)
    }

    func testChargingUsesTimeToFull() {
        let s = BatteryReader.parse(referenceFixture())
        XCTAssertEqual(s.minutesRemaining, 328)
    }

    func testInvalidTimeEstimateBecomesNil() {
        var fixture = referenceFixture()
        fixture["IsCharging"] = false
        fixture["AvgTimeToEmpty"] = 65535
        fixture["TimeRemaining"] = 65535
        let s = BatteryReader.parse(fixture)
        XCTAssertNil(s.minutesRemaining)
    }

    /// Fully charged on AC: IOKit emits huge non-sentinel garbage in
    /// `AvgTimeToEmpty` (observed 2026-10-17: the panel showed
    /// "277h 21m remaining" at 100%). Anything beyond 24 h is nonsense.
    func testGarbageLargeTimeEstimateBecomesNil() {
        var fixture = referenceFixture()
        fixture["IsCharging"] = false
        fixture["FullyCharged"] = true
        fixture["AvgTimeToFull"] = 65535
        fixture["AvgTimeToEmpty"] = 16_641 // 277 h 21 m — the observed garbage
        fixture["TimeRemaining"] = 57_878 // 40-day variant seen live
        let s = BatteryReader.parse(fixture)
        XCTAssertNil(s.minutesRemaining)
    }

    /// Estimates inside the physically plausible range still parse.
    func testPlausibleTimeEstimateSurvives() {
        var fixture = referenceFixture()
        fixture["IsCharging"] = false
        fixture["AvgTimeToEmpty"] = 1_440 // exactly 24 h — plausible edge
        fixture["TimeRemaining"] = 1_440
        let s = BatteryReader.parse(fixture)
        XCTAssertEqual(s.minutesRemaining, 1_440)
    }

    func testMissingKeysFallBackToZero() {
        let s = BatteryReader.parse([:])
        XCTAssertEqual(s.percentage, 0)
        XCTAssertEqual(s.healthPercent, 0) // guards against divide-by-zero
        XCTAssertFalse(s.isCharging)
        XCTAssertNil(s.minutesRemaining)
        XCTAssertNil(s.adapterWatts)
    }

    // MARK: - New fields (serial, manufacture date, low power, not-charging)

    func testSerialAndLowPowerModeParsed() {
        var fixture = referenceFixture()
        fixture["BatterySerialNumber"] = "F9D1234ABC"
        fixture["IsLowPowerMode"] = true

        let s = BatteryReader.parse(fixture)
        XCTAssertEqual(s.serialNumber, "F9D1234ABC")
        XCTAssertTrue(s.isLowPowerMode)
    }

    func testLowPowerModeDefaultsToFalse() {
        XCTAssertFalse(BatteryReader.parse(referenceFixture()).isLowPowerMode)
    }

    func testManufactureDateStringPreferred() {
        var fixture = referenceFixture()
        fixture["ManufactureDate"] = "2023-07-14"

        let s = BatteryReader.parse(fixture)
        XCTAssertNotNil(s.manufactureDate)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.year, .month, .day], from: s.manufactureDate!)
        XCTAssertEqual(comps.year, 2023)
        XCTAssertEqual(comps.month, 7)
        XCTAssertEqual(comps.day, 14)
    }

    func testManufactureDatePackedValue() {
        var fixture = referenceFixture()
        // 2023-07-14 packed: year offset 43 (1980+43=2023), month 7, day 14.
        // (43 << 9) | (7 << 5) | 14 = 22254
        fixture["ManufactureDate"] = 22_254

        let s = BatteryReader.parse(fixture)
        guard let parsed = s.manufactureDate else {
            return XCTFail("packed manufacture date did not decode")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.year, .month, .day], from: parsed)
        XCTAssertEqual(comps.year, 2023)
        XCTAssertEqual(comps.month, 7)
        XCTAssertEqual(comps.day, 14)
    }

    func testManufactureDateInvalidPackedValueYieldsNil() {
        var fixture = referenceFixture()
        // Month 13 and day 0 are both invalid → nil.
        fixture["ManufactureDate"] = (43 << 9) | (13 << 5) | 14
        XCTAssertNil(BatteryReader.parse(fixture).manufactureDate)

        fixture["ManufactureDate"] = (43 << 9) | (7 << 5) | 0
        XCTAssertNil(BatteryReader.parse(fixture).manufactureDate)
    }

    func testPluggedInAndChargingYieldsNoNotChargingReason() {
        let s = BatteryReader.parse(referenceFixture())
        XCTAssertNil(s.notChargingReason)
    }

    func testPluggedInNotChargingYieldsOptimizedChargingHold() {
        var fixture = referenceFixture()
        fixture["IsCharging"] = false
        fixture["FullyCharged"] = false
        fixture["ChargeInhibited"] = true
        fixture["Temperature"] = 3_050 // 30.5 °C — inside the charging window

        let s = BatteryReader.parse(fixture)
        XCTAssertEqual(s.notChargingReason, .optimizedChargingHold)
    }

    func testFullyChargedYieldsFullyChargedReason() {
        var fixture = referenceFixture()
        fixture["IsCharging"] = false
        fixture["FullyCharged"] = true

        XCTAssertEqual(BatteryReader.parse(fixture).notChargingReason, .fullyCharged)
    }

    func testHighTemperatureHold() {
        var fixture = referenceFixture()
        fixture["IsCharging"] = false
        fixture["ChargeInhibited"] = true
        fixture["Temperature"] = 5_000 // 50 °C — above the charging window

        XCTAssertEqual(BatteryReader.parse(fixture).notChargingReason, .temperatureHold)
    }

    func testLegacyChargeStatusTwoYieldsSystemHold() {
        var fixture = referenceFixture()
        fixture["IsCharging"] = false
        fixture["FullyCharged"] = false
        fixture["ChargeStatus"] = 2

        XCTAssertEqual(BatteryReader.parse(fixture).notChargingReason, .systemHold)
    }

    func testNotChargingOnBatteryPowerYieldsNil() {
        var fixture = referenceFixture()
        fixture["IsCharging"] = false
        fixture["ExternalConnected"] = false

        XCTAssertNil(BatteryReader.parse(fixture).notChargingReason)
    }

    func testNotChargingReasonExplanations() {
        XCTAssertEqual(BatterySnapshot.NotChargingReason.fullyCharged.explanation, "battery is fully charged")
        XCTAssertEqual(BatterySnapshot.NotChargingReason.optimizedChargingHold.explanation, "Optimized Charging is holding the level")
        XCTAssertEqual(BatterySnapshot.NotChargingReason.temperatureHold.explanation, "temperature is outside the charging range")
        XCTAssertEqual(BatterySnapshot.NotChargingReason.systemHold.explanation, "the system is holding the charge level")
    }
}
