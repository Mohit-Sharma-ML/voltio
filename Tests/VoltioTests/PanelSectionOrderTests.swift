import Testing
import Foundation
@testable import Voltio

/// Tests for the reorderable menu-panel section order
/// (Settings → Menu Bar → Panel Sections → drag to reorder).
@MainActor
@Suite("Panel section ordering")
struct PanelSectionOrderTests {

    private func makeSettings(_ name: String) -> AppSettings {
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return AppSettings(defaults: suite)
    }

    @Test("Default order matches the declared case order")
    func defaultOrder() {
        let settings = makeSettings("test.section.default")
        #expect(settings.panelSectionOrder == AppSettings.PanelSection.allCases)
        #expect(settings.orderedPanelSections == [.batteryInfo, .devices])
    }

    @Test("Reversed order round-trips through persistence")
    func reversedOrderPersists() {
        let suite = UserDefaults(suiteName: "test.section.reverse")!
        suite.removePersistentDomain(forName: "test.section.reverse")

        let settings = AppSettings(defaults: suite)
        settings.panelSectionOrder = [.devices, .batteryInfo]
        #expect(settings.orderedPanelSections == [.devices, .batteryInfo])

        // A fresh instance reading the same domain must restore the order.
        let reloaded = AppSettings(defaults: suite)
        #expect(reloaded.orderedPanelSections == [.devices, .batteryInfo])
    }

    @Test("Missing sections append at the end")
    func missingSectionsAppend() {
        let settings = makeSettings("test.section.missing")
        settings.panelSectionOrder = [.devices]   // batteryInfo omitted
        #expect(settings.orderedPanelSections == [.devices, .batteryInfo])
    }

    @Test("Unknown raw values in storage are dropped, not crash")
    func unknownValuesDropped() {
        let suite = UserDefaults(suiteName: "test.section.unknown")!
        suite.removePersistentDomain(forName: "test.section.unknown")
        // Simulate a future/legacy stored value that doesn't decode.
        suite.set(Data("not json".utf8), forKey: "panelSectionOrder")
        let settings = AppSettings(defaults: suite)
        #expect(settings.orderedPanelSections == AppSettings.PanelSection.allCases)
    }

    @Test("movePanelSectionUp swaps with the previous section")
    func moveUp() {
        let settings = makeSettings("test.section.up")
        settings.panelSectionOrder = [.devices, .batteryInfo]
        settings.movePanelSectionUp(.batteryInfo)
        #expect(settings.orderedPanelSections == [.batteryInfo, .devices])
    }

    @Test("movePanelSectionDown swaps with the next section")
    func moveDown() {
        let settings = makeSettings("test.section.down")
        settings.movePanelSectionDown(.batteryInfo)
        #expect(settings.orderedPanelSections == [.devices, .batteryInfo])
    }

    @Test("Moving past the ends is a no-op")
    func movePastEnds() {
        let settings = makeSettings("test.section.edges")
        settings.movePanelSectionUp(.batteryInfo)     // already first
        #expect(settings.orderedPanelSections == [.batteryInfo, .devices])
        settings.movePanelSectionDown(.devices)       // already last
        #expect(settings.orderedPanelSections == [.batteryInfo, .devices])
    }

    @Test("resetPanelSectionOrder restores the default")
    func reset() {
        let settings = makeSettings("test.section.reset")
        settings.panelSectionOrder = [.devices, .batteryInfo]
        settings.resetPanelSectionOrder()
        #expect(settings.orderedPanelSections == AppSettings.PanelSection.allCases)
    }
}
