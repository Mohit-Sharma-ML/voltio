import AppKit
import SwiftUI

/// Manages Voltio's single app window (the Settings / dashboard) directly in
/// AppKit. SwiftUI's `Settings` scene can't be opened or observed reliably on
/// macOS 14+, so hosting the SwiftUI view in an `NSWindow` we own lets us:
///   • open it deterministically at launch and on Dock/Applications reopen, and
///   • tie the Dock icon precisely to the window's lifecycle (shown while the
///     window is open, hidden when it closes).
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private var settings: AppSettings?
    private var model: BatteryModel?

    /// Injected once at app launch so the controller can build the window lazily.
    func configure(settings: AppSettings, model: BatteryModel) {
        self.settings = settings
        self.model = model
    }

    /// The shared model, for callers that need to nudge app-level state (e.g. the launch safety net
    /// that brings Bluetooth up if onboarding never finishes).
    var sharedModel: BatteryModel? { model }

    /// Create (if needed) and bring the window forward, raising the Dock icon.
    func show() {
        guard let settings, let model else { return }

        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(settings: settings, model: model)
            )
            let win = NSWindow(contentViewController: hosting)
            win.title = AppInfo.name
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 820, height: 620))
            win.isReleasedWhenClosed = false      // reuse across open/close cycles
            win.identifier = NSUserInterfaceItemIdentifier("VoltioMain")
            win.delegate = self

            // Follow the app appearance preference: nil un-pins the window so
            // it cascades from NSApp.appearance (kept in sync with the setting
            // by VoltioApp), instead of the old hard-coded darkAqua pin.
            win.appearance = nil
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            // Adaptive backdrop: dark value preserved for dark appearance, a
            // light neutral so the chrome doesn't flash dark in Light mode.
            win.backgroundColor = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(red: 0.065, green: 0.067, blue: 0.078, alpha: 1)
                    : NSColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1)
            }

            win.center()
            window = win
            syncWindowAppearance()
        } else {
            // Re-pinning on every open keeps the window correct even if the
            // preference changed while it was closed.
            syncWindowAppearance()
        }

        ActivationPolicy.settingsWindow(open: true)   // .regular → Dock icon appears
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the window drops the Dock icon (unless "always keep in Dock" is on);
    /// the menu-bar item always remains.
    func windowWillClose(_ notification: Notification) {
        ActivationPolicy.settingsWindow(open: false)
    }

    /// Pin the window's appearance to the current preference. Relying on the
    /// nil-cascade from `NSApp.appearance` is not enough for AppKit-backed
    /// subcontrols (e.g. NSPopUpButton): when the preference changes while the
    /// window is live, those cells keep their cached label color and render
    /// white-on-white in Light mode. Setting `window.appearance` explicitly
    /// forces `effectiveAppearance` to re-resolve immediately.
    func syncWindowAppearance() {
        guard let window else { return }
        window.appearance = settings?.preferredAppearance.nsAppearanceName
            .flatMap { NSAppearance(named: $0) }
    }
}
