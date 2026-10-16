import Carbon.HIToolbox
import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

/// Per-device low-battery alert override (set via the Devices pane's bell icon).
/// `color`/`sound` are optional: when nil the global accessory alert styling
/// applies, otherwise the device's own choice wins.
struct DeviceAlertConfig: Codable, Hashable {
    var enabled: Bool
    var threshold: Int
    var color: AlertColor? = nil
    var sound: AlertSound? = nil
}

/// A global-shortcut key binding: a virtual key code plus Carbon modifier
/// flags (e.g. `shiftKey | cmdKey`). Persisted as two Ints in `UserDefaults`
/// so Settings can offer "Reset to default shortcuts" without custom decode.
struct ShortcutCombo: Codable, Hashable {
    var keyCode: Int
    var modifiers: Int

    /// Human-readable rendering like "⇧⌘I" for the Settings rows.
    var display: String {
        var out = ""
        if modifiers & Int(controlKey) != 0 { out += "⌃" }
        if modifiers & Int(optionKey) != 0 { out += "⌥" }
        if modifiers & Int(shiftKey) != 0 { out += "⇧" }
        if modifiers & Int(cmdKey) != 0 { out += "⌘" }
        out += Self.keyGlyph(keyCode)
        return out
    }

    /// Maps virtual key codes for letters/digits to their glyphs; anything
    /// else falls back to a bare code so unknown bindings still render.
    private static func keyGlyph(_ keyCode: Int) -> String {
        switch keyCode {
        case Int(kVK_ANSI_A): return "A"
        case Int(kVK_ANSI_B): return "B"
        case Int(kVK_ANSI_C): return "C"
        case Int(kVK_ANSI_D): return "D"
        case Int(kVK_ANSI_E): return "E"
        case Int(kVK_ANSI_F): return "F"
        case Int(kVK_ANSI_G): return "G"
        case Int(kVK_ANSI_H): return "H"
        case Int(kVK_ANSI_I): return "I"
        case Int(kVK_ANSI_J): return "J"
        case Int(kVK_ANSI_K): return "K"
        case Int(kVK_ANSI_L): return "L"
        case Int(kVK_ANSI_M): return "M"
        case Int(kVK_ANSI_N): return "N"
        case Int(kVK_ANSI_O): return "O"
        case Int(kVK_ANSI_P): return "P"
        case Int(kVK_ANSI_Q): return "Q"
        case Int(kVK_ANSI_R): return "R"
        case Int(kVK_ANSI_S): return "S"
        case Int(kVK_ANSI_T): return "T"
        case Int(kVK_ANSI_U): return "U"
        case Int(kVK_ANSI_V): return "V"
        case Int(kVK_ANSI_W): return "W"
        case Int(kVK_ANSI_X): return "X"
        case Int(kVK_ANSI_Y): return "Y"
        case Int(kVK_ANSI_Z): return "Z"
        default: return String(keyCode)
        }
    }
}

/// User preferences, persisted to `UserDefaults`. Launch-at-login is backed by
/// `SMAppService` (its real state is the source of truth, not a stored flag).
@MainActor
@Observable
final class AppSettings {

    /// A reorderable card-group in the menu panel dropdown. The user drags
    /// these to change the stacking order; anything missing from the stored
    /// order (e.g. a section added in an update) appends at the end.
    enum PanelSection: String, CaseIterable, Identifiable, Codable {
        case batteryInfo
        case devices

        var id: String { rawValue }

        var label: String {
            switch self {
            case .batteryInfo: return "Battery Information"
            case .devices: return "Devices"
            }
        }

        var icon: String {
            switch self {
            case .batteryInfo: return "battery.100percent"
            case .devices: return "keyboard"  // devices: keyboards, mice, AirPods
            }
        }

        var detail: String {
            switch self {
            case .batteryInfo: return "Health, temperature, power flow"
            case .devices: return "Bluetooth accessories"
            }
        }
    }

    /// Menu-bar glyph size. Regular matches the system menu-bar text height;
    /// Large is the easiest to read at a glance.
    enum MenuBarIconSize: String, CaseIterable, Identifiable {
        case regular
        case large

        var id: String { rawValue }

        var label: String {
            switch self {
            case .regular: return "Regular"
            case .large: return "Large"
            }
        }

        var detail: String {
            switch self {
            case .regular: return "Standard menu-bar height"
            case .large: return "Taller glyph, easier to read"
            }
        }

        /// Glyph height in points for the live status item.
        var glyphHeight: CGFloat {
            switch self {
            case .regular: return 15
            case .large: return 20
            }
        }

        /// Height used by the settings preview strip.
        var previewHeight: CGFloat {
            switch self {
            case .regular: return 16
            case .large: return 22
            }
        }
    }

    /// The glyph drawn in the menu bar.
    enum MenuBarIconStyle: String, CaseIterable, Identifiable {
        case batteryIndicator
        case minimal
        case logo

        var id: String { rawValue }

        var label: String {
            switch self {
            case .batteryIndicator: return "Battery Indicator"
            case .minimal: return "Minimal"
            case .logo: return "Voltio Logo"
            }
        }

        var detail: String {
            switch self {
            case .batteryIndicator: return "Battery level and charging status"
            case .minimal: return "Just a clean battery glyph, no text"
            case .logo: return "Static Voltio bolt"
            }
        }
    }

    /// The value shown next to the icon.
    enum MenuBarValue: String, CaseIterable, Identifiable {
        case percentage
        case time
        case none

        var id: String { rawValue }

        var label: String {
            switch self {
            case .percentage: return "Percentage"
            case .time: return "Time remaining"
            case .none: return "Nothing"
            }
        }
    }

    /// On-screen alert bubble size.
    enum BubbleSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var label: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Default"
            case .large: return "Large"
            }
        }
        var scale: CGFloat {
            switch self {
            case .small: return 0.9
            case .medium: return 1.0
            case .large: return 1.18
            }
        }
    }

    /// Strength of the screen-edge glow that accompanies an alert.
    enum GlowIntensity: String, CaseIterable, Identifiable {
        case off, subtle, standard, strong
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: return "Off"
            case .subtle: return "Subtle"
            case .standard: return "Default"
            case .strong: return "Strong"
            }
        }
        var multiplier: CGFloat {
            switch self {
            case .off: return 0
            case .subtle: return 0.55
            case .standard: return 1.0
            case .strong: return 1.6
            }
        }
    }

    /// App-wide color scheme: follow the system, or force Light/Dark.
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "Match System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        /// SwiftUI color scheme applied via `preferredColorScheme`;
        /// `nil` for `.system` so the system setting decides.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }

        /// AppKit appearance name applied via `NSApp.appearance`; `nil` for
        /// `.system` so windows inherit the system appearance.
        var nsAppearanceName: NSAppearance.Name? {
            switch self {
            case .system: return nil
            case .light: return .aqua
            case .dark: return .darkAqua
            }
        }
    }

    /// How often battery telemetry is polled.
    enum RefreshInterval: Int, CaseIterable, Identifiable {
        case fast = 2
        case normal = 5
        case relaxed = 10
        case slow = 30

        var id: Int { rawValue }
        var duration: Duration { .seconds(rawValue) }

        var label: String {
            switch self {
            case .fast: return "Every 2 seconds"
            case .normal: return "Every 5 seconds"
            case .relaxed: return "Every 10 seconds"
            case .slow: return "Every 30 seconds"
            }
        }
    }

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

    // MARK: Device helpers

    /// The panel's sections in display order: the user's stored order first
    /// (drag to reorder in Settings → Menu Bar), then any sections missing
    /// from it — so a section added in an app update still shows up.
    var orderedPanelSections: [PanelSection] {
        let stored = panelSectionOrder
        let missing = PanelSection.allCases.filter { !stored.contains($0) }
        return stored.filter { PanelSection.allCases.contains($0) } + missing
    }

    /// Moves `section` up one slot in the stored order (no-op at the top).
    func movePanelSectionUp(_ section: PanelSection) {
        movePanelSection(section, offset: -1)
    }

    /// Moves `section` down one slot in the stored order (no-op at the end).
    func movePanelSectionDown(_ section: PanelSection) {
        movePanelSection(section, offset: +1)
    }

    private func movePanelSection(_ section: PanelSection, offset: Int) {
        var order = orderedPanelSections
        guard let index = order.firstIndex(of: section) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        panelSectionOrder = order
    }

    /// Restores the default section order (Battery Information first).
    func resetPanelSectionOrder() {
        panelSectionOrder = PanelSection.allCases
    }

    func isDeviceHidden(_ id: String) -> Bool { hiddenDeviceIDs.contains(id) }

    func setDeviceHidden(_ id: String, _ hidden: Bool) {
        if hidden { hiddenDeviceIDs.insert(id) } else { hiddenDeviceIDs.remove(id) }
    }

    func isDevicePinned(_ id: String) -> Bool { pinnedDeviceIDs.contains(id) }

    func setDevicePinned(_ id: String, _ pinned: Bool) {
        if pinned { pinnedDeviceIDs.insert(id) } else { pinnedDeviceIDs.remove(id) }
    }

    /// Effective (enabled, threshold) alert config for a device: its own override
    /// if set, otherwise the global accessory defaults.
    func effectiveDeviceAlert(_ id: String) -> DeviceAlertConfig {
        deviceAlerts[id] ?? DeviceAlertConfig(
            enabled: accessoryLowAlertEnabled, threshold: accessoryLowThreshold
        )
    }

    // MARK: Alert rule helpers

    func addRule(_ category: AlertCategory) {
        alertRules.append(.new(category))
    }

    func removeRule(_ id: UUID) {
        alertRules.removeAll { $0.id == id }
    }

    func resetRules() {
        alertRules = BatteryAlertRule.defaults
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

    private enum Keys {
        static let menuBarIconStyle = "menuBarIconStyle"
        static let menuBarValue = "menuBarValue"
        static let menuBarIconSize = "menuBarIconSize"
        static let statusColors = "statusColors"
        static let showInDock = "showInDock"
        static let refreshInterval = "refreshInterval"
        static let accessoryAlert = "accessoryLowAlertEnabled"
        static let accessoryThreshold = "accessoryLowThreshold"
        static let alertRules = "alertRules"
        static let pluggedAlert = "pluggedInAlertEnabled"
        static let pluggedSound = "pluggedInSound"
        static let unpluggedAlert = "unpluggedAlertEnabled"
        static let unpluggedSound = "unpluggedInSound"
        static let underpoweredAdapterAlert = "underpoweredAdapterAlertEnabled"
        static let hotkeysEnabled = "hotkeysEnabled"
        static let toggleBatteryInfoShortcut = "toggleBatteryInfoShortcut"
        static let toggleDevicesShortcut = "toggleDevicesShortcut"
        static let toggleEnergyAppsShortcut = "toggleEnergyAppsShortcut"
        static let expandBatteryInfo = "expandBatteryInfo"
        static let showEnergyCard = "showEnergyCard"
        static let showEnergyApps = "showEnergyApps"
        static let panelSectionOrder = "panelSectionOrder"
        static let bubbleSize = "bubbleSize"
        static let glowIntensity = "glowIntensity"
        static let alertHoldSeconds = "alertHoldSeconds"
        static let showDevices = "showConnectedDevices"
        static let hiddenDevices = "hiddenDeviceIDs"
        static let pinnedDevices = "pinnedDeviceIDs"
        static let deviceAlerts = "deviceAlerts"
        static let settingsSchemaVersion = "settingsSchemaVersion"
        static let notificationsEnabled = "notificationsEnabled"
        static let developerMode = "developerMode"
        static let fakeBatteryPercent = "fakeBatteryPercent"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let preferredAppearance = "preferredAppearance"
    }
}
