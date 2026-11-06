import Foundation
import IOKit
import IOKit.ps
import PowerCore

/// Startup health checks for the platform-fragile seams Voltio depends on.
/// Surfaced in Settings → Devices →
/// Developer so "the Devices section is empty" becomes a 10-second
/// diagnosis instead of archaeology.
///
/// All checks are cheap, local, in-process reads — no radio activity, no
/// subprocess spawning on the main actor (pmset-style reads are
/// deliberately NOT done here; see the 2026-10-16 IOPS-crash lesson).
@MainActor
enum PlatformHealth {

    /// One seam's pass/fail state.
    struct Check: Identifiable, Equatable {
        let id: String
        let name: String
        let passed: Bool
        let detail: String

        static func == (lhs: Check, rhs: Check) -> Bool { lhs.id == rhs.id }
    }

    /// Run every check. Call from the Developer pane's refresh button —
    /// never on launch polling paths.
    static func runChecks(bluetoothAccess: BluetoothAccess) -> [Check] {
        [
            batteryIOKitCheck,
            powerSourceCheck,
            bluetoothEntitlementCheck(bluetoothAccess),
            appGroupCheck,
        ]
    }

    // MARK: - Individual seams

    /// IOKit battery dictionary readable (the telemetry floor — everything
    /// else is decorative without this). Same read path as BatteryReader.
    private static var batteryIOKitCheck: Check {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else {
            return Check(
                id: "iokit", name: "Battery IOKit",
                passed: false,
                detail: "AppleSmartBattery service not found — panel would show the error state")
        }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, properties?.takeRetainedValue() != nil else {
            return Check(
                id: "iokit", name: "Battery IOKit",
                passed: false,
                detail: "Battery properties unavailable — see the macOS IOKit notes in the troubleshooting docs")
        }
        return Check(id: "iokit", name: "Battery IOKit", passed: true, detail: "Readable")
    }

    /// Power-source notifications flowing (IOPS create is the canary) —
    /// same C signature PowerSourceMonitor uses in production.
    private static var powerSourceCheck: Check {
        // Non-capturing callback (C function pointer) + unretained context:
        // the probe never fires because the source is never scheduled on a
        // run loop — creation alone proves the IOPS machinery is alive.
        let callback: IOPowerSourceCallbackType = { _ in }
        let context = Unmanaged.passUnretained(Self.selfBox).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?
            .takeRetainedValue(),
            CFRunLoopSourceIsValid(source)
        else {
            return Check(
                id: "powerSource", name: "Power-source events",
                passed: false, detail: "IOPS creation failed — see the macOS IOKit notes in the troubleshooting docs")
        }
        return Check(
            id: "powerSource", name: "Power-source events",
            passed: true, detail: "IOPS machinery responsive")
    }

    private static let selfBox = NSObject()

    /// CoreBluetooth authorization state (entitlement + TCC combined — the
    /// 2026-10-17 regression made this silently .unauthorized).
    private static func bluetoothEntitlementCheck(_ access: BluetoothAccess) -> Check {
        switch access {
        case .scanning:
            return Check(id: "bt", name: "Bluetooth access", passed: true, detail: "Authorized, powered on")
        case .poweredOff:
            return Check(id: "bt", name: "Bluetooth access", passed: false, detail: "Bluetooth is powered off (user-toggleable)")
        case .denied:
            return Check(id: "bt", name: "Bluetooth access", passed: false, detail: "Permission denied — enable Voltio in System Settings → Privacy & Security → Bluetooth")
        case .restricted:
            return Check(id: "bt", name: "Bluetooth access", passed: false, detail: "Restricted by device-management policy — no self-service remedy; IT must allow Voltio")
        case .awaitingPermission:
            return Check(id: "bt", name: "Bluetooth access", passed: false, detail: "Permission not requested yet — macOS prompts on the first scan")
        case .unavailable:
            return Check(id: "bt", name: "Bluetooth access", passed: false, detail: "Radio unavailable — verify the Bluetooth entitlement + permission")
        }
    }

    /// App Group container present — the widget pipeline's floor.
    private static var appGroupCheck: Check {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupConfiguration.appGroupID)
        else {
            return Check(
                id: "appGroup", name: "App Group container",
                passed: false,
                detail: "Group container missing — widget cannot receive data — rebuild with scripts/build_app.sh")
        }
        // Read-only existence probe (never write test data into the shared suite).
        let exists = (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
        return Check(
            id: "appGroup", name: "App Group container",
            passed: exists,
            detail: exists ? "Present: \(url.lastPathComponent)" : "Container path missing — rebuild with scripts/build_app.sh")
    }
}
