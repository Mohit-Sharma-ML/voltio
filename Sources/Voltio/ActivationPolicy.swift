import AppKit

/// Centralizes the app's activation policy so menu-bar/Dock behavior stays
/// consistent whether driven by the "Show in Dock" preference or by the
/// Settings window (which temporarily needs a Dock presence to come forward).
@MainActor
enum ActivationPolicy {
    private static var baseShowInDock = false
    private static var settingsOpen = false

    /// Apply the persisted "Show in Dock" preference (called at launch and on change).
    static func apply(showInDock: Bool) {
        baseShowInDock = showInDock
        reconcile()
    }

    /// The Settings window forces `.regular` while open so it always activates.
    static func settingsWindow(open: Bool) {
        settingsOpen = open
        reconcile()
        if open { NSApp.activate(ignoringOtherApps: true) }
    }

    private static func reconcile() {
        let policy: NSApplication.ActivationPolicy =
            (baseShowInDock || settingsOpen) ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}
