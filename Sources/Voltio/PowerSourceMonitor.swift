import Foundation
import IOKit.ps

/// Delivers *instant* notifications when the power state changes — charger
/// plugged/unplugged, charge level, or time-remaining — via IOKit's power-source
/// run-loop source. This is what makes the menu bar and alerts react immediately
/// instead of waiting for the next poll tick.
@MainActor
final class PowerSourceMonitor {
    private var runLoopSource: CFRunLoopSource?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard runLoopSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        // Non-capturing so it bridges to a C function pointer. The source is added
        // to the main run loop, so the callback fires on the main thread.
        let callback: IOPowerSourceCallbackType = { rawContext in
            guard let rawContext else { return }
            MainActorIsolation.assume {
                Unmanaged<PowerSourceMonitor>.fromOpaque(rawContext)
                    .takeUnretainedValue()
                    .onChange()
            }
        }

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?
            .takeRetainedValue()
        else { return }

        runLoopSource = source
        // Common modes so it still fires while the run loop is in a tracking mode.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
    }
}
