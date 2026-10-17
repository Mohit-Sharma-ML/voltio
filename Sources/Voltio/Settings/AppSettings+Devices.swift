import Foundation

/// Device visibility/pinning/alert-override helpers. Extracted from
/// AppSettings.swift the underlying
/// stored properties stay in the core file.
extension AppSettings {

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
}
