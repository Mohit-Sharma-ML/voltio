import Testing
import Foundation
import SwiftUI
@testable import Voltio

@MainActor
@Suite("App appearance setting")
struct AppearanceSettingTests {
    private func makeSettings(_ name: String) -> AppSettings {
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return AppSettings(defaults: suite)
    }

    private func reloadSettings(_ name: String) -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: name)!)
    }

    @Test("Default appearance is system")
    func defaultIsSystem() {
        let settings = makeSettings("AppearanceDefault")
        #expect(settings.preferredAppearance == .system)
    }

    @Test("Appearance preference persists across reload")
    func persistenceRoundTrip() {
        let settings = makeSettings("AppearancePersist")
        settings.preferredAppearance = .dark
        #expect(reloadSettings("AppearancePersist").preferredAppearance == .dark)
        settings.preferredAppearance = .light
        #expect(reloadSettings("AppearancePersist").preferredAppearance == .light)
    }

    @Test("colorScheme mapping: system is nil, light/dark resolve")
    func colorSchemeMapping() {
        #expect(AppSettings.Appearance.system.colorScheme == nil)
        #expect(AppSettings.Appearance.light.colorScheme == .light)
        #expect(AppSettings.Appearance.dark.colorScheme == .dark)
    }

    @Test("nsAppearanceName mapping: system is nil, light/dark resolve")
    func nsAppearanceNameMapping() {
        #expect(AppSettings.Appearance.system.nsAppearanceName == nil)
        #expect(AppSettings.Appearance.light.nsAppearanceName == NSAppearance.Name.aqua)
        #expect(AppSettings.Appearance.dark.nsAppearanceName == NSAppearance.Name.darkAqua)
    }

    @Test("Labels describe each choice")
    func labels() {
        #expect(AppSettings.Appearance.system.label == "Match System")
        #expect(AppSettings.Appearance.light.label == "Light")
        #expect(AppSettings.Appearance.dark.label == "Dark")
    }

    @Test("Exactly three appearance choices")
    func threeCases() {
        #expect(AppSettings.Appearance.allCases.count == 3)
    }
}
