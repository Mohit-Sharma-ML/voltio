import AppKit

/// The recovery path for a denied Bluetooth permission.
///
/// macOS shows the TCC prompt once. After a denial it never asks again, so the
/// privacy pane in System Settings is the only way back — every surface that
/// reports the denial has to offer it, or the message is a dead end. Kept in
/// one place so the URL cannot drift between the panel and Settings.
enum BluetoothPrivacySettings {
    static let url: URL? = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
    )

    static func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
