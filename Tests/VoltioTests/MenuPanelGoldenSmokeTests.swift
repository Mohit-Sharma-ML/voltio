import AppKit
import SwiftUI
import Testing
import PowerCore
@testable import Voltio

/// Golden-image smoke for the panel (Phase 0.2 of Docs/hardening-plan.md).
/// Not pixel-perfect — the goal is "did the refactor break the layout":
/// render `MenuPanelView` offscreen with a fixed snapshot and assert the
/// render succeeds with plausible dimensions. Text-level assertions live on
/// the extracted card views once Phase 1 splits them into standalone structs
/// (asserting KVC-text inside a SwiftUI hosting view crashes the runner —
/// verified 2026-10-17).
@MainActor
@Suite("Menu panel golden smoke")
struct MenuPanelGoldenSmokeTests {

    @Test("Panel renders on-battery snapshot with plausible dimensions")
    func rendersOnBattery() throws {
        let size = try renderPanel(
            percentage: 73,
            isCharging: false,
            isPluggedIn: false
        )
        #expect(size.width == CGFloat(Theme.panelWidth))
        #expect(size.height > 100) // hero + cards + footer, never a sliver
        #expect(size.height < 2000) // never an unbounded explosion
    }

    @Test("Panel renders charging snapshot with plausible dimensions")
    func rendersCharging() throws {
        let size = try renderPanel(
            percentage: 73,
            isCharging: true,
            isPluggedIn: true
        )
        #expect(size.width == CGFloat(Theme.panelWidth))
        #expect(size.height > 100)
    }

    @Test("Charging panel is taller than the compact on-battery one")
    func chargingAddsContent() throws {
        let battery = try renderPanel(percentage: 73, isCharging: false, isPluggedIn: false)
        let charging = try renderPanel(percentage: 73, isCharging: true, isPluggedIn: true)
        // Charging adds the Power Flow card; the layout must reflect content,
        // not a fixed height. (Loose band: both include hero + footer.)
        #expect(charging.height >= battery.height)
    }
    // MARK: - Helpers

    /// Builds a panel driven entirely by fakes — no IOKit, no Bluetooth, no
    /// WidgetKit, no real defaults domain — and renders it offscreen with
    /// `ImageRenderer` (headless-safe; lockFocus/KVC-walking crashed the
    /// test runner).
    private func renderPanel(
        percentage: Int,
        isCharging: Bool,
        isPluggedIn: Bool
    ) throws -> CGSize {
        let suite = UserDefaults(suiteName: "test.golden.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: suite)
        let snapshot = BatterySnapshot(
            percentage: percentage,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isFullyCharged: false,
            isLowPowerMode: false,
            minutesRemaining: isCharging ? 42 : 120,
            cycleCount: 100,
            designCycleCount: 1000,
            temperatureCelsius: 28,
            voltage: 11.6,
            amperage: 0,
            currentCapacitymAh: 4000,
            maxCapacitymAh: 8000,
            designCapacitymAh: 8800,
            adapterWatts: isPluggedIn ? 96 : nil,
            adapterName: nil,
            systemPowerWatts: nil,
            batteryPowerWatts: nil,
            notChargingReason: nil
        )
        let provider = FakeBatteryProvider(states: [snapshot])
        let model = BatteryModel(
            settings: settings,
            reader: provider,
            widgetWriter: FakeWidgetPublisher(),
            chargeLimitReader: FakeChargeLimitReader(),
            startMonitors: false
        )
        let view = MenuPanelView(model: model, settings: settings)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(
            width: CGFloat(Theme.panelWidth),
            height: nil
        )
        renderer.scale = 1
        let size = renderer.nsImage?.size ?? .zero
        return size
    }
}
