import Foundation
import IOKit
import IOKit.pwr_mgt

/// Observes system sleep/wake via IOKit's root-domain power notifications, so
/// Voltio can catch up the moment the Mac wakes: poll timers and IOKit
/// power-source notifications are both suspended during sleep, meaning a
/// battery that crossed an alert threshold overnight would otherwise stay
/// silent until the next poll tick.
///
/// Uses the canonical `IORegisterForSystemPower` API — a single interest
/// callback on the root power domain delivering `kIOMessageSystemWillSleep`,
/// `kIOMessageSystemWillPowerOn`, and `kIOMessageSystemHasPoweredOn`.
/// IOKit's `kIOMessageSystem*` constants are function-like macros
/// (`iokit_common_msg(0x280)`), which the Clang importer does not expose to
/// Swift. These mirror the exact `UInt32` values (sys_iokit | sub_iokit_common | code).
private enum PowerMessage {
    static let systemWillSleep: UInt32 = 0xE000_0280
    static let systemWillPowerOn: UInt32 = 0xE000_0320
    static let systemHasPoweredOn: UInt32 = 0xE000_0300
}

@MainActor
final class SleepWakeObserver {
    private let onSleep: () -> Void
    private let onWake: () -> Void

    /// `nonisolated(unsafe)` lets the nonisolated `deinit` read these opaque
    /// C handles (`IONotificationPortRef`/`io_connect_t` are non-Sendable);
    /// teardown only needs the raw values, not actor synchronization.
    nonisolated(unsafe) private var notifyPort: IONotificationPortRef?
    nonisolated(unsafe) private var powerConnection: io_connect_t = 0

    init(onSleep: @escaping () -> Void, onWake: @escaping () -> Void) {
        self.onSleep = onSleep
        self.onWake = onWake
    }

    func start() {
        guard notifyPort == nil else { return }

        // Non-capturing so it bridges to a C function pointer. The port is
        // drained on the main run loop, so the callback fires on the main
        // thread — same contract PowerSourceMonitor relies on.
        let callback: IOServiceInterestCallback = { _, _, messageType, rawContext in
            guard let rawContext else { return }
            MainActorIsolation.assume {
                let observer = Unmanaged<SleepWakeObserver>
                    .fromOpaque(rawContext).takeUnretainedValue()
                switch messageType {
                case PowerMessage.systemWillSleep:
                    observer.onSleep()
                case PowerMessage.systemWillPowerOn, PowerMessage.systemHasPoweredOn:
                    observer.onWake()
                default:
                    break
                }
            }
        }

        var port: IONotificationPortRef?
        let status = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(), &port, callback, &powerConnection
        )
        // kIOReturnSuccess == 0 and a valid port are both required.
        guard status == kIOReturnSuccess, let port else {
            if let port { IONotificationPortDestroy(port) }
            return
        }
        notifyPort = port

        if let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            // Common modes so the wake still fires while other run-loop modes
            // are active during login/resume.
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    deinit {
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
        }
        if powerConnection != 0 {
            IOServiceClose(powerConnection)
        }
    }
}
