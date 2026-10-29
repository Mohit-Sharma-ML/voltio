import AppKit

/// The only recovery path after a Bluetooth denial (macOS never re-prompts); kept in one place so it can't drift.
enum BluetoothPrivacySettings {
    static let url: URL? = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
    )

    static func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
