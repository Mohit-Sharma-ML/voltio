import Foundation
import PowerCore

/// Abstractions over `BatteryModel`'s collaborators so the model's decision
/// logic (poll gating, widget reload throttling, sleep/wake caching, alert
/// dispatch) can be characterized-tested with fakes. The concrete
/// implementations are the production types; `BatteryModel` takes them via
/// its initializer with production defaults.

/// Provides the Mac's internal battery reading.
public protocol BatteryReadingProviding: Sendable {
    func read() throws -> BatterySnapshot
}

extension BatteryReader: BatteryReadingProviding {}

/// Publishes widget snapshots to the App Group. Exists so tests can observe
/// publish calls (and reload decisions) without touching WidgetKit. The
/// default `date`/`forceReload` parameters live only on the concrete type;
/// the protocol pins the shape `BatteryModel` actually calls.
public protocol WidgetPublishing: AnyObject {
    func publish(
        _ snapshot: BatterySnapshot,
        todayEnergy: EnergyAggregator.DayTotal?,
        smoothedPowerWatts: Double?,
        at date: Date,
        forceReload: Bool
    )
}

extension WidgetSnapshotWriter: WidgetPublishing {}

/// Reads the native macOS charge-limit configuration.
public protocol ChargeLimitReading: Sendable {
    func read() -> ChargeLimitState
}

extension ChargeLimitReader: ChargeLimitReading {}

/// Delivers system sleep/wake notifications. Exists so the model's
/// sleep/wake handling (pre-sleep caching, wake catch-up) can be
/// characterized-tested with a fake that simulates the transitions.
/// `SleepWakeObserver` (its production implementation) declares conformance
/// directly.
@MainActor
public protocol SleepWakeNotifying: AnyObject {
    /// Invoked when the system is about to sleep (point of no return).
    var onSleep: (() -> Void)? { get set }
    /// Invoked when the system has fully woken.
    var onWake: (() -> Void)? { get set }
    /// Begin delivering notifications. Idempotent.
    func start()
}
