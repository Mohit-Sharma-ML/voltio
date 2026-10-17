import Foundation

/// UserDefaults key names for every persisted setting. Extracted from
/// AppSettings.swift (Phase 1.1 of Docs/hardening-plan.md). Internal (not
/// `private`) so the didSet wiring in the core file can use it.
extension AppSettings {

    enum Keys {
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
