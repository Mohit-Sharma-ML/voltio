import Testing
import Foundation
import Carbon.HIToolbox
@testable import Voltio

/// Tests for the configurable global toggle shortcuts
/// (Settings → Shortcuts): default bindings, persistence across reload,
/// reset-to-defaults, and the panel visibility flags they toggle.
@MainActor
@Suite("Toggle shortcut bindings")
struct ToggleShortcutTests {

    private func makeSettings(_ name: String) -> AppSettings {
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return AppSettings(defaults: suite)
    }

    /// A fresh instance over the same (already-populated) domain — used to
    /// verify persistence across relaunch without wiping stored values.
    private func reloadSettings(_ name: String) -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: name)!)
    }

    @Test("Factory defaults are ⇧⌘I, ⇧⌘D, ⇧⌘E")
    func factoryDefaults() {
        let settings = makeSettings("test.shortcut.defaults")

        #expect(settings.toggleBatteryInfoShortcut == AppSettings.defaultToggleBatteryInfo)
        #expect(settings.toggleDevicesShortcut == AppSettings.defaultToggleDevices)
        #expect(settings.toggleEnergyAppsShortcut == AppSettings.defaultToggleEnergyApps)

        #expect(settings.toggleBatteryInfoShortcut.display == "⇧⌘I")
        #expect(settings.toggleDevicesShortcut.display == "⇧⌘D")
        #expect(settings.toggleEnergyAppsShortcut.display == "⇧⌘E")
    }

    @Test("Defaults don't collide with each other and render as ⇧⌘ combos")
    func defaultsAreDistinctFromFixedShortcuts() {
        let combos = [
            AppSettings.defaultToggleBatteryInfo,
            AppSettings.defaultToggleDevices,
            AppSettings.defaultToggleEnergyApps,
        ]
        // All three defaults are distinct from each other.
        #expect(Set(combos).count == 3)
        // And each is a shift+command combo (glyph prefix ⇧⌘, matching the
        // panel ⇧⌘B / settings ⇧⌘S style family).
        for combo in combos {
            #expect(combo.display.hasPrefix("⇧⌘"))
        }
    }

    @Test("Custom binding persists and reloads")
    func customBindingPersists() {
        let settings = makeSettings("test.shortcut.custom")
        settings.toggleBatteryInfoShortcut = ShortcutCombo(keyCode: 12, modifiers: 1)
        #expect(settings.toggleBatteryInfoShortcut.keyCode == 12)

        // A fresh instance reading the same domain must restore the binding.
        let reloaded = reloadSettings("test.shortcut.custom")
        #expect(reloaded.toggleBatteryInfoShortcut.keyCode == 12)
        #expect(reloaded.toggleBatteryInfoShortcut.modifiers == 1)
    }

    @Test("resetShortcutBindings restores factory defaults")
    func resetRestoresDefaults() {
        let settings = makeSettings("test.shortcut.reset")

        settings.toggleBatteryInfoShortcut = ShortcutCombo(keyCode: 1, modifiers: 2)
        settings.toggleDevicesShortcut = ShortcutCombo(keyCode: 3, modifiers: 4)
        settings.toggleEnergyAppsShortcut = ShortcutCombo(keyCode: 5, modifiers: 6)

        settings.resetShortcutBindings()

        #expect(settings.toggleBatteryInfoShortcut == AppSettings.defaultToggleBatteryInfo)
        #expect(settings.toggleDevicesShortcut == AppSettings.defaultToggleDevices)
        #expect(settings.toggleEnergyAppsShortcut == AppSettings.defaultToggleEnergyApps)
    }

    @Test("expandBatteryInfo persists across reload")
    func expandBatteryInfoPersists() {
        let suite = UserDefaults(suiteName: "test.shortcut.expand")!
        suite.removePersistentDomain(forName: "test.shortcut.expand")

        let settings = AppSettings(defaults: suite)
        #expect(settings.expandBatteryInfo == false)
        settings.expandBatteryInfo = true

        let reloaded = AppSettings(defaults: suite)
        #expect(reloaded.expandBatteryInfo == true)
    }

    @Test("showEnergyCard defaults to visible and persists when hidden")
    func showEnergyCardPersists() {
        let suite = UserDefaults(suiteName: "test.shortcut.energy")!
        suite.removePersistentDomain(forName: "test.shortcut.energy")

        let settings = AppSettings(defaults: suite)
        #expect(settings.showEnergyCard == true)
        settings.showEnergyCard = false

        let reloaded = AppSettings(defaults: suite)
        #expect(reloaded.showEnergyCard == false)
    }

    @Test("ShortcutCombo.display renders modifier glyphs in canonical order")
    func displayRendersModifiers() {
        // ⌃⌥⇧⌘ + key letter, matching the glyph order in `display`.
        let all = ShortcutCombo(
            keyCode: Int(kVK_ANSI_R),
            modifiers: Int(controlKey) | Int(optionKey) | Int(shiftKey) | Int(cmdKey)
        )
        #expect(all.display == "⌃⌥⇧⌘R")

        let shiftOnly = ShortcutCombo(keyCode: Int(kVK_ANSI_R), modifiers: shiftKey)
        #expect(shiftOnly.display == "⇧R")

        let none = ShortcutCombo(keyCode: Int(kVK_ANSI_R), modifiers: 0)
        #expect(none.display == "R")
    }
}
