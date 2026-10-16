import Foundation
import PowerCore
import Testing
@testable import Voltio

// MARK: - Snapshot helper

private func makeSnapshot(
    percentage: Int,
    isPluggedIn: Bool,
    isCharging: Bool = false,
    isFullyCharged: Bool = false,
    notChargingReason: BatterySnapshot.NotChargingReason? = nil
) -> BatterySnapshot {
    BatterySnapshot(
        percentage: percentage,
        isCharging: isCharging,
        isPluggedIn: isPluggedIn,
        isFullyCharged: isFullyCharged,
        minutesRemaining: nil,
        cycleCount: 0,
        designCycleCount: 1000,
        temperatureCelsius: 30,
        voltage: 12.5,
        amperage: 0,
        currentCapacitymAh: 4000,
        maxCapacitymAh: 5000,
        designCapacitymAh: 5000,
        adapterWatts: isPluggedIn ? 60 : nil,
        adapterName: isPluggedIn ? "Test Adapter" : nil,
        systemPowerWatts: nil,
        batteryPowerWatts: nil,
        notChargingReason: notChargingReason
    )
}

/// Verifies how `BatteryDisplay` maps `NotChargingReason` states to the hero
/// status pill: a macOS hold while plugged in must read
/// "Paused by macOS" with a pause icon, while thermal holds, "fully charged",
/// charging, and plain on-battery states keep their own labels.
@Suite("BatteryDisplay paused status")
struct BatteryDisplayPausedStatusTests {

    @Test("Optimized charging hold maps to Paused by macOS")
    func optimizedHold() {
        let s = makeSnapshot(
            percentage: 80,
            isPluggedIn: true,
            notChargingReason: .optimizedChargingHold
        )
        #expect(s.isPausedByMacOS)
        #expect(s.statusText == "Paused by macOS")
        #expect(s.statusIcon == "bolt.pause.fill")
    }

    @Test("System policy hold maps to Paused by macOS")
    func systemHold() {
        let s = makeSnapshot(
            percentage: 65,
            isPluggedIn: true,
            notChargingReason: .systemHold
        )
        #expect(s.isPausedByMacOS)
        #expect(s.statusText == "Paused by macOS")
        #expect(s.statusIcon == "bolt.pause.fill")
    }

    @Test("Fully charged keeps its own label, not paused")
    func fullyCharged() {
        let s = makeSnapshot(
            percentage: 100,
            isPluggedIn: true,
            isFullyCharged: true,
            notChargingReason: .fullyCharged
        )
        #expect(!s.isPausedByMacOS)
        #expect(s.statusText == "Fully charged")
        #expect(s.statusIcon == "powerplug.fill")
    }

    @Test("Temperature hold stays plugged-in label")
    func temperatureHold() {
        let s = makeSnapshot(
            percentage: 55,
            isPluggedIn: true,
            notChargingReason: .temperatureHold
        )
        #expect(!s.isPausedByMacOS)
        #expect(s.statusText == "Plugged in")
        #expect(s.statusIcon == "powerplug.fill")
    }

    @Test("Charging while plugged in never counts as paused")
    func charging() {
        let s = makeSnapshot(
            percentage: 42,
            isPluggedIn: true,
            isCharging: true,
            notChargingReason: nil
        )
        #expect(!s.isPausedByMacOS)
        #expect(s.statusText == "Charging")
        #expect(s.statusIcon == "bolt.fill")
    }

    @Test("Hold reason is ignored when running on battery")
    func onBatteryIgnoresHold() {
        let s = makeSnapshot(
            percentage: 42,
            isPluggedIn: false,
            notChargingReason: .systemHold
        )
        #expect(!s.isPausedByMacOS)
        #expect(s.statusText == "On battery")
        #expect(s.statusIcon == "battery.50percent")
    }

    @Test("Plugged in with no hold reason keeps Plugged in")
    func plainPluggedIn() {
        let s = makeSnapshot(
            percentage: 42,
            isPluggedIn: true,
            notChargingReason: nil
        )
        #expect(!s.isPausedByMacOS)
        #expect(s.statusText == "Plugged in")
        #expect(s.statusIcon == "powerplug.fill")
    }

    @Test("Paused state survives percentage override")
    func overridePreservesPaused() {
        let s = makeSnapshot(
            percentage: 80,
            isPluggedIn: true,
            notChargingReason: .optimizedChargingHold
        )
        let overridden = s.overridingPercentage(12)
        #expect(overridden.notChargingReason == .optimizedChargingHold)
        #expect(overridden.isPausedByMacOS)
        #expect(overridden.statusText == "Paused by macOS")
    }
}
