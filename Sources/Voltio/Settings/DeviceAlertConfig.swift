/// Per-device low-battery alert override (set via the Devices pane's bell icon).
/// `color`/`sound` are optional: when nil the global accessory alert styling
/// applies, otherwise the device's own choice wins.
struct DeviceAlertConfig: Codable, Hashable {
    var enabled: Bool
    var threshold: Int
    var color: AlertColor? = nil
    var sound: AlertSound? = nil
}

