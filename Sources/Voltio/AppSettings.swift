import Carbon.HIToolbox
import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

/// User preferences, persisted to `UserDefaults`. Launch-at-login is backed by
/// `SMAppService` (its real state is the source of truth, not a stored flag).
@MainActor
@Observable
final class AppSettings {

    var menuBarIconStyle: MenuBarIconStyle {
        didSet { defaults.set(menuBarIconStyle.rawValue, forKey: Keys.menuBarIconStyle) }
    }

    var menuBarValue: MenuBarValue {
        didSet { defaults.set(menuBarValue.rawValue, forKey: Keys.menuBarValue) }
    }

    /// Whether the menu-bar glyph renders at regular or large size.
    var menuBarIconSize: MenuBarIconSize {
        didSet { defaults.set(menuBarIconSize.rawValue, forKey: Keys.menuBarIconSize) }
    }

    /// Tint the menu-bar icon by charge state (green charging, orange low, red critical).
    var statusColors: Bool {
        didSet { defaults.set(statusColors, forKey: Keys.statusColors) }
    }

    /// Show Voltio in the Dock (in addition to the menu bar).
    var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: Keys.showInDock)
            ActivationPolicy.apply(showInDock: showInDock)
        }
    }

    var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval) }
    }

    var launchAtLogin: Bool {
        didSet {
            guard !isReconciling else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    // MARK: Alerts

    /// All configurable low-battery and charged alerts. Each rule carries its own
    /// threshold, color, on-screen position, sound, glow, and persistence. Stored
    /// as JSON in `UserDefaults`.
    var alertRules: [BatteryAlertRule] {
        didSet { persistRules() }
    }

    /// Warn when a connected accessory (AirPods, Magic devices…) runs low. Acts as
    /// the default for any device without its own per-device override.
    var accessoryLowAlertEnabled: Bool {
        didSet { defaults.set(accessoryLowAlertEnabled, forKey: Keys.accessoryAlert) }
    }

    /// Percentage (5–50) at which an accessory low-battery warning fires.
    var accessoryLowThreshold: Int {
        didSet { defaults.set(accessoryLowThreshold, forKey: Keys.accessoryThreshold) }
    }

    // MARK: Power source alerts

    /// Alert when the power adapter is connected.
    var pluggedInAlertEnabled: Bool {
        didSet { defaults.set(pluggedInAlertEnabled, forKey: Keys.pluggedAlert) }
    }
    var pluggedInSound: AlertSound {
        didSet { persist(pluggedInSound, forKey: Keys.pluggedSound) }
    }

    /// Alert when the power adapter is disconnected.
    var unpluggedAlertEnabled: Bool {
        didSet { defaults.set(unpluggedAlertEnabled, forKey: Keys.unpluggedAlert) }
    }
    var unpluggedSound: AlertSound {
        didSet { persist(unpluggedSound, forKey: Keys.unpluggedSound) }
    }

    /// Alert when plugged in but the battery is still draining — the adapter
    /// can't keep up with system draw (undersized charger, hub, DisplayLink…).
    var underpoweredAdapterAlertEnabled: Bool {
        didSet { defaults.set(underpoweredAdapterAlertEnabled, forKey: Keys.underpoweredAdapterAlert) }
    }

    /// Global hotkeys: ⇧⌘B toggles the menu panel, ⇧⌘S opens Settings.
    var hotkeysEnabled: Bool {
        didSet { defaults.set(hotkeysEnabled, forKey: Keys.hotkeysEnabled) }
    }

    // MARK: Toggle shortcuts

    /// Default binding for the battery-info expand/collapse toggle (⇧⌘I).
    static let defaultToggleBatteryInfo = ShortcutCombo(
        keyCode: Int(kVK_ANSI_I), modifiers: shiftKey | cmdKey
    )
    /// Default binding for the devices-section toggle (⇧⌘D).
    static let defaultToggleDevices = ShortcutCombo(
        keyCode: Int(kVK_ANSI_D), modifiers: shiftKey | cmdKey
    )
    /// Default binding for the energy-card toggle (⇧⌘E).
    static let defaultToggleEnergyApps = ShortcutCombo(
        keyCode: Int(kVK_ANSI_E), modifiers: shiftKey | cmdKey
    )

    /// Whether the Battery Information cards in the panel are expanded.
    /// Migrated from the former raw `@AppStorage("expandBatteryInfo")` so the
    /// global shortcut can toggle it (and tests can verify persistence).
    var expandBatteryInfo: Bool {
        didSet { defaults.set(expandBatteryInfo, forKey: Keys.expandBatteryInfo) }
    }

    /// Global toggle shortcut: expand/collapse the Battery Information cards.
    var toggleBatteryInfoShortcut: ShortcutCombo {
        didSet {
            guard toggleBatteryInfoShortcut != oldValue else { return }
            persist(toggleBatteryInfoShortcut, forKey: Keys.toggleBatteryInfoShortcut)
        }
    }

    /// Global toggle shortcut: show/hide the Devices section in the panel.
    var toggleDevicesShortcut: ShortcutCombo {
        didSet {
            guard toggleDevicesShortcut != oldValue else { return }
            persist(toggleDevicesShortcut, forKey: Keys.toggleDevicesShortcut)
        }
    }

    /// Global toggle shortcut: show/hide the Energy Today card in the panel.
    var toggleEnergyAppsShortcut: ShortcutCombo {
        didSet {
            guard toggleEnergyAppsShortcut != oldValue else { return }
            persist(toggleEnergyAppsShortcut, forKey: Keys.toggleEnergyAppsShortcut)
        }
    }

    /// Whether the "Energy Today" card is shown in the panel (data permitting).
    /// Toggling the shortcut flips this visibility.
    var showEnergyCard: Bool {
        didSet { defaults.set(showEnergyCard, forKey: Keys.showEnergyCard) }
    }

    /// Whether the per-app energy list is shown in the panel's battery info
    /// section. Populates only while on battery, once two sampler ticks exist.
    var showEnergyApps: Bool {
        didSet { defaults.set(showEnergyApps, forKey: Keys.showEnergyApps) }
    }

    /// Restores all toggle shortcuts to their factory bindings (⇧⌘I/⇧⌘D/⇧⌘E).
    func resetShortcutBindings() {
        toggleBatteryInfoShortcut = Self.defaultToggleBatteryInfo
        toggleDevicesShortcut = Self.defaultToggleDevices
        toggleEnergyAppsShortcut = Self.defaultToggleEnergyApps
    }

    /// User's custom top-to-bottom order for the panel's card groups (drag to
    /// reorder in Settings → Menu Bar). Not every case must be present —
    /// `orderedPanelSections` appends any missing sections at the end.
    var panelSectionOrder: [PanelSection] {
        didSet {
            guard panelSectionOrder != oldValue else { return }
            persist(panelSectionOrder, forKey: Keys.panelSectionOrder)
        }
    }

    // MARK: Appearance

    /// App-wide look: follow the system, or force Light/Dark.
    var preferredAppearance: Appearance {
        didSet { defaults.set(preferredAppearance.rawValue, forKey: Keys.preferredAppearance) }
    }

    // MARK: Notification appearance

    /// On-screen alert bubble size.
    var bubbleSize: BubbleSize {
        didSet { defaults.set(bubbleSize.rawValue, forKey: Keys.bubbleSize) }
    }

    /// Strength of the screen-edge glow.
    var glowIntensity: GlowIntensity {
        didSet { defaults.set(glowIntensity.rawValue, forKey: Keys.glowIntensity) }
    }

    /// How long a non-persistent alert bubble stays on screen, in seconds.
    var alertHoldSeconds: Double {
        didSet { defaults.set(alertHoldSeconds, forKey: Keys.alertHoldSeconds) }
    }

    // MARK: Devices

    /// Show paired Bluetooth/accessory battery in the menu-bar dropdown.
    var showConnectedDevices: Bool {
        didSet { defaults.set(showConnectedDevices, forKey: Keys.showDevices) }
    }

    /// Devices the user has hidden from the menu-bar dropdown.
    var hiddenDeviceIDs: Set<String> {
        didSet { defaults.set(Array(hiddenDeviceIDs), forKey: Keys.hiddenDevices) }
    }

    /// Devices pinned to the menu bar: their battery glyph renders next to the
    /// main Mac battery even when the dropdown is closed.
    var pinnedDeviceIDs: Set<String> {
        didSet { defaults.set(Array(pinnedDeviceIDs), forKey: Keys.pinnedDevices) }
    }

    /// Per-device low-battery alert overrides, keyed by device id.
    var deviceAlerts: [String: DeviceAlertConfig] {
        didSet { persist(deviceAlerts, forKey: Keys.deviceAlerts) }
    }

    // MARK: Notifications

    /// Also deliver battery alerts as macOS system notifications (works when
    /// the menu-bar bubble is missed — full-screen apps, Do Not Disturb).
    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    // MARK: Developer

    /// Reveals diagnostic surfaces (BLE counters, simulated battery) in the UI.
    var developerMode: Bool {
        didSet { defaults.set(developerMode, forKey: Keys.developerMode) }
    }

    /// Simulated battery percentage used when the fake-battery developer
    /// override is on. `nil` = live readings.
    var fakeBatteryPercent: Int? {
        didSet {
            if let value = fakeBatteryPercent {
                defaults.set(value, forKey: Keys.fakeBatteryPercent)
            } else {
                defaults.removeObject(forKey: Keys.fakeBatteryPercent)
            }
        }
    }

    // MARK: Onboarding

    /// Whether the first-launch onboarding has been shown and acknowledged.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    private func persistRules() {
        persist(alertRules, forKey: Keys.alertRules)
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Surfaced in the UI if registering the login item fails.
    private(set) var launchAtLoginError: String?

    private let defaults: UserDefaults
    private var isReconciling = false

    /// Bump when the shape of persisted settings changes in a way that needs a
    /// migration (renamed keys, semantic change of a stored value, etc.). The
    /// version is stamped into `UserDefaults` on first launch so future
    /// migrations can detect and upgrade old data. Currently informational —
    /// no migrations exist yet.
    static let currentSchemaVersion = 1

    private(set) var settingsSchemaVersion: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Stamp the schema version on first launch so migrations can detect
        // which version of the settings shape is on disk.
        let stored = defaults.object(forKey: Keys.settingsSchemaVersion) as? Int
        self.settingsSchemaVersion = stored ?? Self.currentSchemaVersion
        if stored == nil {
            defaults.set(Self.currentSchemaVersion, forKey: Keys.settingsSchemaVersion)
        }
        let iconRaw = defaults.string(forKey: Keys.menuBarIconStyle)
        self.menuBarIconStyle = MenuBarIconStyle(rawValue: iconRaw ?? "") ?? .batteryIndicator
        let valueRaw = defaults.string(forKey: Keys.menuBarValue)
        self.menuBarValue = MenuBarValue(rawValue: valueRaw ?? "") ?? .percentage
        let sizeRaw = defaults.string(forKey: Keys.menuBarIconSize)
        self.menuBarIconSize = MenuBarIconSize(rawValue: sizeRaw ?? "") ?? .regular
        let intervalRaw = defaults.object(forKey: Keys.refreshInterval) as? Int
        self.refreshInterval = intervalRaw.flatMap(RefreshInterval.init(rawValue:)) ?? .normal
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)

        func storedBool(_ key: String, default value: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
        }
        func storedInt(_ key: String, default value: Int) -> Int {
            defaults.object(forKey: key) == nil ? value : defaults.integer(forKey: key)
        }
        func storedDouble(_ key: String, default value: Double) -> Double {
            defaults.object(forKey: key) == nil ? value : defaults.double(forKey: key)
        }
        self.statusColors = storedBool(Keys.statusColors, default: true)
        self.showInDock = storedBool(Keys.showInDock, default: false)
        self.accessoryLowAlertEnabled = storedBool(Keys.accessoryAlert, default: true)
        self.accessoryLowThreshold = storedInt(Keys.accessoryThreshold, default: 20)

        self.pluggedInAlertEnabled = storedBool(Keys.pluggedAlert, default: false)
        self.unpluggedAlertEnabled = storedBool(Keys.unpluggedAlert, default: false)
        self.underpoweredAdapterAlertEnabled = storedBool(Keys.underpoweredAdapterAlert, default: false)
        self.hotkeysEnabled = storedBool(Keys.hotkeysEnabled, default: true)

        // Toggle-shortcut bindings. A stored value wins; otherwise the factory
        // defaults apply. Decode failure (corrupt data) falls back to defaults.
        // Inlined decode (not `self.decode`) because `self` isn't fully
        // initialized yet at this point in `init`.
        func storedCombo(_ key: String, default combo: ShortcutCombo) -> ShortcutCombo {
            defaults.data(forKey: key)
                .flatMap { try? JSONDecoder().decode(ShortcutCombo.self, from: $0) } ?? combo
        }
        self.toggleBatteryInfoShortcut = storedCombo(
            Keys.toggleBatteryInfoShortcut, default: Self.defaultToggleBatteryInfo)
        self.toggleDevicesShortcut = storedCombo(
            Keys.toggleDevicesShortcut, default: Self.defaultToggleDevices)
        self.toggleEnergyAppsShortcut = storedCombo(
            Keys.toggleEnergyAppsShortcut, default: Self.defaultToggleEnergyApps)
        // Migrates the former raw @AppStorage("expandBatteryInfo") in the panel.
        self.expandBatteryInfo = storedBool(Keys.expandBatteryInfo, default: false)
        self.showEnergyCard = storedBool(Keys.showEnergyCard, default: true)
        self.showEnergyApps = storedBool(Keys.showEnergyApps, default: true)

        self.panelSectionOrder = (defaults.data(forKey: Keys.panelSectionOrder))
            .flatMap { try? JSONDecoder().decode([PanelSection].self, from: $0) } ?? PanelSection.allCases

        let appearanceRaw = defaults.string(forKey: Keys.preferredAppearance)
        self.preferredAppearance = Appearance(rawValue: appearanceRaw ?? "") ?? .system

        let bubbleRaw = defaults.string(forKey: Keys.bubbleSize)
        self.bubbleSize = BubbleSize(rawValue: bubbleRaw ?? "") ?? .medium
        let glowRaw = defaults.string(forKey: Keys.glowIntensity)
        self.glowIntensity = GlowIntensity(rawValue: glowRaw ?? "") ?? .standard
        // Clamp on load so a stale/corrupt value can't pin a bubble forever.
        self.alertHoldSeconds = min(max(storedDouble(Keys.alertHoldSeconds, default: 3), 2), 8)

        self.showConnectedDevices = storedBool(Keys.showDevices, default: true)
        self.hiddenDeviceIDs = Set(defaults.stringArray(forKey: Keys.hiddenDevices) ?? [])
        self.pinnedDeviceIDs = Set(defaults.stringArray(forKey: Keys.pinnedDevices) ?? [])

        self.notificationsEnabled = storedBool(Keys.notificationsEnabled, default: false)
        self.developerMode = storedBool(Keys.developerMode, default: false)
        self.fakeBatteryPercent = defaults.object(forKey: Keys.fakeBatteryPercent) as? Int
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        // Decodable members are loaded after stored defaults via the `decode` helper.
        func loadSound(_ key: String, default value: AlertSound) -> AlertSound {
            (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode(AlertSound.self, from: $0) } ?? value
        }
        self.pluggedInSound = loadSound(Keys.pluggedSound, default: .system("Tink"))
        self.unpluggedSound = loadSound(Keys.unpluggedSound, default: .none)

        self.deviceAlerts = (defaults.data(forKey: Keys.deviceAlerts))
            .flatMap { try? JSONDecoder().decode([String: DeviceAlertConfig].self, from: $0) } ?? [:]

        if let data = defaults.data(forKey: Keys.alertRules),
           let rules = try? JSONDecoder().decode([BatteryAlertRule].self, from: data) {
            self.alertRules = rules
        } else {
            self.alertRules = BatteryAlertRule.defaults
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let status) where status != .enabled:
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            // Revert the toggle to the real service state without re-triggering.
            isReconciling = true
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            isReconciling = false
        }
    }

}
