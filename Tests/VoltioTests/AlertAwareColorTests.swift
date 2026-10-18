import Foundation
import SwiftUI
import PowerCore
import Testing
@testable import Voltio

// MARK: - Snapshot helper

private func makeSnapshot(
    percentage: Int,
    isPluggedIn: Bool,
    isCharging: Bool = false
) -> BatterySnapshot {
    BatterySnapshot(
        percentage: percentage,
        isCharging: isCharging,
        isPluggedIn: isPluggedIn,
        isFullyCharged: false,
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
        notChargingReason: nil
    )
}

private func rule(
    _ category: AlertCategory,
    threshold: Int,
    color: AlertColor,
    enabled: Bool = true
) -> BatteryAlertRule {
    BatteryAlertRule(
        category: category,
        threshold: threshold,
        color: color,
        position: .top,
        sound: .none,
        borderGlow: false,
        persistent: false,
        enabled: enabled
    )
}

/// Verifies that the hero accent color (`alertAwareColor`) reflects the user's
/// own alert rules once the level crosses an enabled threshold — and falls
/// back to the generic state color when nothing matches.
@Suite("Alert-aware ring color")
struct AlertAwareColorTests {

    // MARK: Low rules, on battery

    @Test("Level below low threshold wears that rule's color")
    func lowMatch() {
        let s = makeSnapshot(percentage: 15, isPluggedIn: false)
        let color = s.alertAwareColor(rules: [
            rule(.low, threshold: 20, color: .orange),
            rule(.low, threshold: 10, color: .red),
        ])
        #expect(color == .orange)
    }

    @Test("Most severe crossed low rule wins")
    func lowSeverity() {
        let s = makeSnapshot(percentage: 8, isPluggedIn: false)
        let color = s.alertAwareColor(rules: [
            rule(.low, threshold: 20, color: .orange),
            rule(.low, threshold: 10, color: .red),
        ])
        #expect(color == .red)
    }

    @Test("Level above all low thresholds falls back to state color")
    func lowNoMatch() {
        let s = makeSnapshot(percentage: 45, isPluggedIn: false)
        let color = s.alertAwareColor(rules: [rule(.low, threshold: 20, color: .orange)])
        #expect(color == s.stateColor)
    }

    @Test("Disabled low rules are ignored")
    func lowDisabled() {
        let s = makeSnapshot(percentage: 15, isPluggedIn: false)
        let color = s.alertAwareColor(rules: [
            rule(.low, threshold: 20, color: .orange, enabled: false)
        ])
        #expect(color == s.stateColor)
    }

    // MARK: Charged rules, on AC

    @Test("Level at/above charged threshold wears that rule's color")
    func chargedMatch() {
        let s = makeSnapshot(percentage: 95, isPluggedIn: true, isCharging: false)
        let color = s.alertAwareColor(rules: [
            rule(.charged, threshold: 80, color: .green),
            rule(.charged, threshold: 90, color: .teal),
        ])
        #expect(color == .teal)
    }

    @Test("Plugged in below charged thresholds falls back to state color")
    func chargedNoMatch() {
        let s = makeSnapshot(percentage: 50, isPluggedIn: true, isCharging: true)
        let color = s.alertAwareColor(rules: [rule(.charged, threshold: 80, color: .green)])
        #expect(color == s.stateColor)
    }

    // MARK: Defaults mirror the shipped rule set

    @Test("Default rules: 15% on battery is orange, 8% is red")
    func defaultRules() {
        let rules = BatteryAlertRule.defaults
        #expect(makeSnapshot(percentage: 15, isPluggedIn: false)
            .alertAwareColor(rules: rules) == .orange)
        #expect(makeSnapshot(percentage: 8, isPluggedIn: false)
            .alertAwareColor(rules: rules) == .red)
        #expect(makeSnapshot(percentage: 83, isPluggedIn: false)
            .alertAwareColor(rules: rules) == s83StateColor)
        #expect(makeSnapshot(percentage: 85, isPluggedIn: true)
            .alertAwareColor(rules: rules) == .green)
    }

    private var s83StateColor: Color {
        makeSnapshot(percentage: 83, isPluggedIn: false).stateColor
    }
}
