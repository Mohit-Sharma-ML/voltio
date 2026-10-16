import Foundation
@testable import PowerCore
import Testing

/// Round-trip and presentation behavior of the App Group handoff payload.
struct WidgetSnapshotTests {

    private static let sample = WidgetSnapshot(
        percentage: 80,
        isCharging: false,
        isPluggedIn: false,
        isFullyCharged: false,
        isLowPowerMode: false,
        minutesRemaining: 245,
        systemPowerWatts: 11.8,
        adapterWatts: nil,
        adapterName: nil,
        energyTodayWh: 21.3,
        energySampledMinutes: 141,
        energyAvgWatts: 12.0,
        timestamp: Date(timeIntervalSince1970: 1_792_000_000)
    )

    @Test func jsonRoundTripPreservesAllFields() throws {
        let data = try JSONEncoder().encode(Self.sample)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(decoded == Self.sample)
    }

    @Test func unknownFieldsAreIgnoredOnDecode() throws {
        // A future app adds a field; an older widget must still decode.
        let json = """
        {
            "percentage": 42,
            "isCharging": true,
            "isPluggedIn": true,
            "isFullyCharged": false,
            "isLowPowerMode": false,
            "minutesRemaining": 30,
            "systemPowerWatts": 33.5,
            "adapterWatts": 96,
            "adapterName": "96W USB-C",
            "energyTodayWh": null,
            "energySampledMinutes": null,
            "energyAvgWatts": null,
            "timestamp": 1792000000,
            "someFutureField": "ignored"
        }
        """
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(decoded.percentage == 42)
        #expect(decoded.isCharging == true)
        #expect(decoded.adapterWatts == 96)
    }

    @Test func statusTextCharging() {
        let s = Self.sample
        let charging = WidgetSnapshot(
            percentage: s.percentage, isCharging: true, isPluggedIn: true,
            isFullyCharged: false, isLowPowerMode: false, minutesRemaining: s.minutesRemaining,
            systemPowerWatts: nil, adapterWatts: nil, adapterName: nil,
            energyTodayWh: nil, energySampledMinutes: nil, energyAvgWatts: nil,
            timestamp: s.timestamp
        )
        #expect(charging.statusText == "Charging")
    }

    @Test func statusTextFullyCharged() {
        let s = Self.sample
        let full = WidgetSnapshot(
            percentage: 100, isCharging: false, isPluggedIn: true,
            isFullyCharged: true, isLowPowerMode: false, minutesRemaining: nil,
            systemPowerWatts: nil, adapterWatts: nil, adapterName: nil,
            energyTodayWh: nil, energySampledMinutes: nil, energyAvgWatts: nil,
            timestamp: s.timestamp
        )
        #expect(full.statusText == "Fully Charged")
    }

    @Test func statusTextLowPowerOnBattery() {
        let s = Self.sample
        let low = WidgetSnapshot(
            percentage: 20, isCharging: false, isPluggedIn: false,
            isFullyCharged: false, isLowPowerMode: true, minutesRemaining: nil,
            systemPowerWatts: nil, adapterWatts: nil, adapterName: nil,
            energyTodayWh: nil, energySampledMinutes: nil, energyAvgWatts: nil,
            timestamp: s.timestamp
        )
        #expect(low.statusText == "Low Power Mode")
    }

    @Test func statusTextOnBattery() {
        #expect(Self.sample.statusText == "On Battery")
    }

    @Test func timeRemainingFormatting() {
        let s = Self.sample
        func with(minutes: Int?) -> WidgetSnapshot {
            WidgetSnapshot(
                percentage: s.percentage, isCharging: s.isCharging, isPluggedIn: s.isPluggedIn,
                isFullyCharged: s.isFullyCharged, isLowPowerMode: s.isLowPowerMode,
                minutesRemaining: minutes,
                systemPowerWatts: nil, adapterWatts: nil, adapterName: nil,
                energyTodayWh: nil, energySampledMinutes: nil, energyAvgWatts: nil,
                timestamp: s.timestamp
            )
        }
        #expect(with(minutes: 245).timeRemainingText == "4 h 05 m left")
        #expect(with(minutes: 120).timeRemainingText == "2 h left")
        #expect(with(minutes: 42).timeRemainingText == "42 m left")
        #expect(with(minutes: 0).timeRemainingText == nil)
        #expect(with(minutes: nil).timeRemainingText == nil)
    }
}
