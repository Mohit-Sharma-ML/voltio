import AppKit
import Carbon.HIToolbox

/// Registers global (system-wide) hotkeys via Carbon's
/// `RegisterEventHotKey` — the standard approach for menu-bar apps, working
/// even when no Voltio window has focus.
///
/// Registered shortcuts:
/// - **⇧⌘B** — toggle the menu panel (open/close the `MenuBarExtra` window)
/// - **⇧⌘S** — open the Settings window
/// - **⇧⌘I** — toggle the Battery Information cards (user-configurable)
/// - **⇧⌘D** — toggle the Devices section (user-configurable)
/// - **⇧⌘E** — toggle the Energy Today card (user-configurable)
///
/// The three toggle shortcuts read their bindings from `AppSettings`
/// (`toggleBatteryInfoShortcut`, `toggleDevicesShortcut`,
/// `toggleEnergyAppsShortcut`); re-registering applies any changes. Failed
/// registrations (key already claimed by another app, reserved combos…) are
/// reported via `registrationFailures` so Settings can surface them.
///
/// Re-registering replaces the previous handlers, so flipping
/// `settings.hotkeysEnabled` off cleanly unregisters everything.
@MainActor
final class HotKeyController {
    /// Tags that identify our hotkeys in the Carbon event callback.
    private enum Tag {
        static let panel: UInt32 = 1
        static let settings: UInt32 = 2
        static let toggleBatteryInfo: UInt32 = 3
        static let toggleDevices: UInt32 = 4
        static let toggleEnergyApps: UInt32 = 5
    }

    private var panelHotKeyRef: EventHotKeyRef?
    private var settingsHotKeyRef: EventHotKeyRef?
    private var batteryInfoHotKeyRef: EventHotKeyRef?
    private var devicesHotKeyRef: EventHotKeyRef?
    private var energyAppsHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Callbacks supplied by the app delegate at launch.
    private var onTogglePanel: (() -> Void)?
    private var onOpenSettings: (() -> Void)?
    private var onToggleBatteryInfo: (() -> Void)?
    private var onToggleDevices: (() -> Void)?
    private var onToggleEnergyApps: (() -> Void)?

    /// One entry per shortcut that failed to register (e.g. claimed by
    /// another app). Settings surfaces these like the login-item error.
    private(set) var registrationFailures: [String] = []

    func install(
        onTogglePanel: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onToggleBatteryInfo: @escaping () -> Void = {},
        onToggleDevices: @escaping () -> Void = {},
        onToggleEnergyApps: @escaping () -> Void = {}
    ) {
        self.onTogglePanel = onTogglePanel
        self.onOpenSettings = onOpenSettings
        self.onToggleBatteryInfo = onToggleBatteryInfo
        self.onToggleDevices = onToggleDevices
        self.onToggleEnergyApps = onToggleEnergyApps
        register()
    }

    /// Re-registers all hotkeys (or removes them when disabled).
    func setEnabled(_ enabled: Bool) {
        unregister()
        if enabled { register() }
    }

    /// Re-applies the current toggle-shortcut bindings from settings
    /// (call after the user changes a binding or resets to defaults).
    func reapplyShortcutBindings(_ settings: AppSettings) {
        // A full unregister/register cycle keeps the failure list fresh.
        setEnabled(settings.hotkeysEnabled)
    }


    /// Settings providing the toggle-shortcut bindings; nil in tests.
    weak var settings: AppSettings?

    private func register() {
        guard eventHandler == nil else { return }
        registrationFailures = []

        // Route Carbon hotkey events to our handler. The callback hops to the
        // main actor: Carbon dispatches events on the main thread (same
        // contract as the IOKit bridges in MainActorIsolation).
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            MainActorIsolation.assume {
                let controller = Unmanaged<HotKeyController>
                    .fromOpaque(userData).takeUnretainedValue()
                controller.handle(event: event)
            }
            return noErr
        }

        let this = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType, this, &eventHandler
        )

        // ⇧⌘B — toggle the menu panel.
        panelHotKeyRef = registerHotkey(
            keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(shiftKey | cmdKey), tag: Tag.panel
        )
        // ⇧⌘S — open Settings.
        settingsHotKeyRef = registerHotkey(
            keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(shiftKey | cmdKey), tag: Tag.settings
        )

        // Toggle shortcuts — bindings come from settings (factory defaults:
        // ⇧⌘I battery info, ⇧⌘D devices, ⇧⌘E energy card).
        if let settings {
            batteryInfoHotKeyRef = registerShortcut(
                settings.toggleBatteryInfoShortcut, tag: Tag.toggleBatteryInfo,
                label: "Toggle Battery Information"
            )
            devicesHotKeyRef = registerShortcut(
                settings.toggleDevicesShortcut, tag: Tag.toggleDevices,
                label: "Toggle Devices"
            )
            energyAppsHotKeyRef = registerShortcut(
                settings.toggleEnergyAppsShortcut, tag: Tag.toggleEnergyApps,
                label: "Toggle Energy Card"
            )
        }
    }

    /// Registers a user-configurable shortcut and records a failure entry if
    /// Carbon rejects it (key already in use by another app, reserved combo…).
    private func registerShortcut(
        _ combo: ShortcutCombo, tag: UInt32, label: String
    ) -> EventHotKeyRef? {
        let ref = registerHotkey(
            keyCode: UInt32(combo.keyCode), modifiers: UInt32(combo.modifiers), tag: tag
        )
        if ref == nil {
            registrationFailures.append(
                "Global shortcut registration failed (\(label): \(combo.display))"
            )
        }
        return ref
    }

    private func registerHotkey(keyCode: UInt32, modifiers: UInt32, tag: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, EventHotKeyID(signature: OSType(0x564F4C54) /* 'VOLT' */, id: tag),
            GetApplicationEventTarget(), 0, &ref
        )
        return status == noErr ? ref : nil
    }

    private func unregister() {
        if let panelHotKeyRef { UnregisterEventHotKey(panelHotKeyRef) }
        if let settingsHotKeyRef { UnregisterEventHotKey(settingsHotKeyRef) }
        if let batteryInfoHotKeyRef { UnregisterEventHotKey(batteryInfoHotKeyRef) }
        if let devicesHotKeyRef { UnregisterEventHotKey(devicesHotKeyRef) }
        if let energyAppsHotKeyRef { UnregisterEventHotKey(energyAppsHotKeyRef) }
        panelHotKeyRef = nil
        settingsHotKeyRef = nil
        batteryInfoHotKeyRef = nil
        devicesHotKeyRef = nil
        energyAppsHotKeyRef = nil
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
    }

    private func handle(event: EventRef) {
        var hotKeyID = EventHotKeyID()
        guard GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
        ) == noErr else { return }

        switch hotKeyID.id {
        case Tag.panel: onTogglePanel?()
        case Tag.settings: onOpenSettings?()
        case Tag.toggleBatteryInfo: onToggleBatteryInfo?()
        case Tag.toggleDevices: onToggleDevices?()
        case Tag.toggleEnergyApps: onToggleEnergyApps?()
        default: break
        }
    }
}

// MARK: - Panel toggling

extension HotKeyController {
    /// Toggles the `MenuBarExtra` window. SwiftUI's MenuBarExtra doesn't expose
    /// a programmatic open/close API, so this finds the status item's window
    /// (owned by the system StatusBarItem window level) and orders it in/out.
    /// Opening follows the same path as a real click: it posts the menu-bar
    /// extra's status item action, which positions the panel under the icon.
    func togglePanel() {
        if let panel = MenuBarExtraWindowFinder.find(), panel.isVisible {
            panel.orderOut(nil)
            return
        }
        // Not visible: find the status item's window (which always exists,
        // even while its menu/panel is closed) and simulate a click so SwiftUI
        // presents the panel anchored to the icon.
        MenuBarExtraWindowFinder.clickStatusItem()
    }
}

/// Helpers for locating the `MenuBarExtra` status item and its panel window.
/// SwiftUI doesn't expose the underlying `NSStatusItem`, so we search by
/// window class and level.
@MainActor
enum MenuBarExtraWindowFinder {
    /// The visible MenuBarExtra *panel* window (`.window` style presents as a
    /// borderless window above the status item). Nil when closed.
    static func find() -> NSWindow? {
        NSApp.windows.first { window in
            window.className.contains("NSStatusBarWindow")
                && window.level == .statusBar
                && window.isVisible
        }
    }

    /// Simulates a click on our status item so SwiftUI opens the panel. The
    /// status item window hosts a button; triggering its action opens the
    /// MenuBarExtra exactly as a real click would.
    static func clickStatusItem() {
        guard let statusBarWindow = NSApp.windows.first(where: {
            $0.className.contains("NSStatusBarWindow") && $0.level == .statusBar
        }) else { return }
        // The button is the window's content view; a programmatic performClick
        // opens the panel anchored to the menu bar.
        if let button = statusBarWindow.contentView?.subviews.compactMap({ $0 as? NSButton }).first {
            button.performClick(nil)
        }
    }
}
