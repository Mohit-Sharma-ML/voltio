import AppKit
import ServiceManagement
import SwiftUI

@main
struct VoltioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: BatteryModel
    @State private var settings: AppSettings

    init() {
        let settings = AppSettings()
        let model = BatteryModel(settings: settings)
        _settings = State(initialValue: settings)
        _model = State(initialValue: model)
        // The app window is managed in AppKit (see MainWindowController); give it
        // the shared settings/model so it can build the window on demand.
        MainWindowController.shared.configure(settings: settings, model: model)
        // Global hotkeys need the delegate's lifecycle; hand it the settings so
        // registration follows the user's toggle.
        AppDelegate.pendingSettings = settings
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(model: model, settings: settings)
                .installOpenWindowBridge()
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
        // First launch only; dismissed via "Get Started".
        Window("Welcome to Voltio", id: "onboarding") {
            OnboardingView(settings: settings)
                .installOpenWindowBridge()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    @ViewBuilder private var menuBarLabel: some View {
        if let image = MenuBarRender.image(settings: settings, model: model) {
            Image(nsImage: image)
        } else {
            Text(model.menuBarTitle)
        }
    }
}

/// Voltio always lives in the menu bar. The Dock icon is *dynamic*:
/// it appears only while a window is open and disappears when the window closes.
/// The "Always keep in Dock" preference forces a permanent Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `VoltioApp.init` before the delegate is invoked.
    nonisolated(unsafe) static var pendingSettings: AppSettings?

    private var hotKeyController: HotKeyController?
    private var hotkeyObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ActivationPolicy.apply(showInDock: UserDefaults.standard.bool(forKey: "showInDock"))

        // Global hotkeys: ⇧⌘B toggles the menu panel, ⇧⌘S opens Settings,
        // plus three user-configurable toggle shortcuts from settings.
        if let settings = Self.pendingSettings {
            // App-wide appearance: apply the saved System/Light/Dark preference
            // and keep NSApp.appearance in sync when the user changes it. A nil
            // appearance un-pins so windows inherit the system look.
            NSApp.appearance = settings.preferredAppearance.nsAppearanceName.flatMap { NSAppearance(named: $0) }
            // The panel window doesn't exist yet at launch (it's created when
            // the panel first opens) — MenuPanelView pins it on every open.
            observeAppearanceSetting(settings)

            let controller = HotKeyController()
            controller.settings = settings
            controller.install(
                onTogglePanel: { [weak controller] in controller?.togglePanel() },
                onOpenSettings: { SettingsLauncher.open() },
                onToggleBatteryInfo: { [weak settings] in
                    settings?.expandBatteryInfo.toggle()
                },
                onToggleDevices: { [weak settings] in
                    settings?.showConnectedDevices.toggle()
                },
                onToggleEnergyApps: { [weak settings] in
                    // ⇧⌘E toggles both energy readouts: the Energy Today card
                    // and the per-app attribution list beneath it.
                    settings?.showEnergyCard.toggle()
                    settings?.showEnergyApps.toggle()
                }
            )
            hotKeyController = controller
            // Re-register when the user flips the global-shortcuts toggle or
            // any of the three shortcut bindings (both via one observation).
            observeHotkeySetting(settings) { [weak controller, weak settings] enabled in
                controller?.setEnabled(enabled)
                _ = settings?.toggleBatteryInfoShortcut
                _ = settings?.toggleDevicesShortcut
                _ = settings?.toggleEnergyAppsShortcut
            }
            observeShortcutBinding(settings) { [weak controller] in
                controller?.reapplyShortcutBindings(settings)
            }
        }

        // A manual launch opens the window (which raises the Dock icon). When the
        // app is launched at login it's already running quietly in the menu bar, so
        // those clicks are handled by `applicationShouldHandleReopen` instead.
        if SMAppService.mainApp.status != .enabled {
            DispatchQueue.main.async { SettingsLauncher.open() }
        }

        // First launch: show onboarding before dropping into menu-bar mode.
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            DispatchQueue.main.async {
                OpenWindow.open(id: "onboarding")
            }
        }
    }

    /// Clicking the Dock/Applications icon (when no window is open) opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsLauncher.open() }
        return true
    }

    /// One-shot `withObservationTracking` that re-arms itself whenever
    /// `hotkeysEnabled` changes. The tracking closure is a synchronous read
    /// performed on the main actor; the change handler hops back to the main
    /// actor (where both the delegate launch path and the Settings toggle live).
    private func observeHotkeySetting(_ settings: AppSettings, onChange: @escaping @MainActor (Bool) -> Void) {
        // `self` (the AppDelegate) is main-thread confined, and the onChange
        // callback fires on the main thread here — the assumeIsolated hop
        // satisfies the @Sendable requirement without a real cross-thread hop.
        nonisolated(unsafe) let appDelegate = self
        withObservationTracking {
            MainActor.assumeIsolated {
                _ = settings.hotkeysEnabled
            }
        } onChange: {
            MainActor.assumeIsolated {
                onChange(settings.hotkeysEnabled)
                appDelegate.observeHotkeySetting(settings, onChange: onChange)
            }
        }
    }

    /// One-shot `withObservationTracking` (same re-arming pattern as
    /// `observeHotkeySetting`) that fires whenever the user changes the
    /// System/Light/Dark appearance preference, so `NSApp.appearance` (and
    /// everything that inherits from it) follows immediately.
    private func observeAppearanceSetting(_ settings: AppSettings) {
        nonisolated(unsafe) let appDelegate = self
        withObservationTracking {
            MainActor.assumeIsolated {
                _ = settings.preferredAppearance
            }
        } onChange: {
            MainActor.assumeIsolated {
                NSApp.appearance = settings.preferredAppearance.nsAppearanceName.flatMap { NSAppearance(named: $0) }
                // Explicitly re-pin the live Settings window too: AppKit-backed
                // subcontrols (NSPopUpButton) don't re-resolve their label color
                // from the nil-cascade alone and stay white-on-white in Light mode.
                MainWindowController.shared.syncWindowAppearance()
                // Re-pin the live panel window as well (it may be open while
                // the user flips the picker): the MenuBarExtraWindow (level
                // 101 — NOT the status item's NSStatusBarWindow) doesn't
                // follow the NSApp cascade on its own, so a Light→Dark flip
                // with the panel visible keeps resolving semantic colors
                // (system green, etc.) with light variants until the next
                // open. Setting the window's appearance explicitly forces an
                // immediate re-resolve; nil under Match System restores the
                // system inheritance. (MenuPanelView pins the same window on
                // every open.)
                let panelAppearance = settings.preferredAppearance.nsAppearanceName.flatMap { NSAppearance(named: $0) }
                for window in NSApp.windows where window.className.contains("MenuBarExtraWindow") {
                    window.appearance = panelAppearance
                }
                appDelegate.observeAppearanceSetting(settings)
            }
        }
    }

    /// One-shot `withObservationTracking` (same re-arming pattern as
    /// `observeHotkeySetting`) that fires whenever one of the three
    /// configurable shortcut bindings changes, so the Carbon registrations
    /// follow the new keys immediately.
    private func observeShortcutBinding(_ settings: AppSettings, onChange: @escaping @MainActor () -> Void) {
        nonisolated(unsafe) let appDelegate = self
        withObservationTracking {
            MainActor.assumeIsolated {
                _ = settings.toggleBatteryInfoShortcut
                _ = settings.toggleDevicesShortcut
                _ = settings.toggleEnergyAppsShortcut
            }
        } onChange: {
            MainActor.assumeIsolated {
                onChange()
                appDelegate.observeShortcutBinding(settings, onChange: onChange)
            }
        }
    }
}
