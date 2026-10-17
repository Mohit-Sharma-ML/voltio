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
    static let canSystemSleep: UInt32 = 0xE000_0270
    static let systemWillSleep: UInt32 = 0xE000_0280
    static let systemWillPowerOn: UInt32 = 0xE000_0320
    static let systemHasPoweredOn: UInt32 = 0xE000_0300
}

@MainActor
final class SleepWakeObserver: SleepWakeNotifying {
    /// Set before `start()`; invoked on system sleep / full wake.
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?

    /// `nonisolated(unsafe)` lets the nonisolated `deinit` read these opaque
    /// C handles (`IONotificationPortRef`/`io_connect_t` are non-Sendable);
    /// teardown only needs the raw values, not actor synchronization.
    nonisolated(unsafe) private var notifyPort: IONotificationPortRef?
    nonisolated(unsafe) private var powerConnection: io_connect_t = 0

    func start() {
        guard notifyPort == nil else { return }

        // Non-capturing so it bridges to a C function pointer. The port is
        // drained on the main run loop, so the callback fires on the main
        // thread — same contract PowerSourceMonitor relies on.
        let callback: IOServiceInterestCallback = { refcon, service, messageType, messageArgument in
            // Acknowledgment contract (IOPMLib.h + Apple QA1340): the
            // root-domain listener MUST answer sleep-family messages with
            // IOAllowPowerChange, or power management stalls the sleep for a
            // 30 s timeout (bad user experience). `messageArgument` carries
            // the notification ID to acknowledge with. Fire the app callbacks
            // after acknowledging.
            switch messageType {
            case PowerMessage.canSystemSleep, PowerMessage.systemWillSleep:
                IOAllowPowerChange(service, Int(bitPattern: messageArgument))
            default:
                break
            }
            guard let refcon else { return }
            MainActorIsolation.assume {
                let observer = Unmanaged<SleepWakeObserver>
                    .fromOpaque(refcon).takeUnretainedValue()
                switch messageType {
                case PowerMessage.systemWillSleep:
                    observer.onSleep?()
                // Restore on FULL wake only. kIOMessageSystemWillPowerOn fires
                // early in the wake sequence — before battery/IOKit state has
                // settled — and both messages also fire during dark wakes
                // (CPU wakes for maintenance while the display stays off).
                // HasPoweredOn is the documented "fully woken" point.
                case PowerMessage.systemHasPoweredOn:
                    observer.onWake?()
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
