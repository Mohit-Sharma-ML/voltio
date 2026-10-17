import Foundation
import PowerCore

/// Abstractions over `BatteryModel`'s collaborators so the model's decision
/// logic (poll gating, widget reload throttling, sleep/wake caching, alert
/// dispatch) can be characterized-tested with fakes. The concrete
/// implementations are the production types; `BatteryModel` takes them via
/// its initializer with production defaults (Phase 0 of the hardening plan —
/// see Docs/hardening-plan.md).

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
