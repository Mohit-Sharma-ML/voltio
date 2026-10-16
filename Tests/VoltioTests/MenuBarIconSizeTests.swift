import Testing
import Foundation
@testable import Voltio

/// Tests for the menu-bar icon size setting
/// (Settings → Menu Bar → Icon Size → Regular/Large).
@MainActor
@Suite("Menu bar icon size")
struct MenuBarIconSizeTests {

    private func makeSettings(_ name: String) -> AppSettings {
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return AppSettings(defaults: suite)
    }

    @Test("Default size is regular")
    func defaultIsRegular() {
        let settings = makeSettings("test.iconsize.default")
        #expect(settings.menuBarIconSize == .regular)
    }

    @Test("Large size persists across instances")
    func largePersists() {
        let suite = UserDefaults(suiteName: "test.iconsize.persist")!
        suite.removePersistentDomain(forName: "test.iconsize.persist")

        let settings = AppSettings(defaults: suite)
        settings.menuBarIconSize = .large
        let reloaded = AppSettings(defaults: suite)
        #expect(reloaded.menuBarIconSize == .large)
    }

    @Test("Corrupt stored value falls back to regular")
    func corruptValueFallsBack() {
        let suite = UserDefaults(suiteName: "test.iconsize.corrupt")!
        suite.removePersistentDomain(forName: "test.iconsize.corrupt")
        suite.set("bogus", forKey: "menuBarIconSize")
        let settings = AppSettings(defaults: suite)
        #expect(settings.menuBarIconSize == .regular)
    }

    @Test("Large glyph is taller than regular")
    func largeIsTaller() {
        #expect(AppSettings.MenuBarIconSize.large.glyphHeight > AppSettings.MenuBarIconSize.regular.glyphHeight)
        #expect(AppSettings.MenuBarIconSize.large.previewHeight > AppSettings.MenuBarIconSize.regular.previewHeight)
    }
}
