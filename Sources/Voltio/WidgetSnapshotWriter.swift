import Foundation
import PowerCore

/// Publishes the latest `WidgetSnapshot` to the App Group UserDefaults suite so
/// the widget extension can render it.
///
/// Transport rationale: the app is non-sandboxed, so App Group *container*
/// directories resolve differently for it than for the (sandboxed) widget.
/// `UserDefaults(suiteName:)` is the one channel that behaves identically for
/// both — the app writes, the widget reads, no file paths involved.
///
/// Writes are best-effort: a failure here is invisible to the user and only
/// means the widget shows its previous timeline until the next tick.
final class WidgetSnapshotWriter {
    /// Must match the App Group in both entitlements files. The Team-ID
    /// prefix is REQUIRED on this platform: sandboxed extensions can only
    /// access team-ID-prefixed group containers (containermanagerd rejects
    /// unprefixed groups). Injected at build time — see `AppGroupConfiguration`.
    static let appGroupID = AppGroupConfiguration.appGroupID

    private let defaults: UserDefaults?

    /// - Parameter defaults: injectable for tests; `nil` uses the App Group suite.
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.appGroupID)
    }

    /// Encodes and publishes one snapshot. Cheap (a few hundred bytes of JSON
    /// every 5 s); the system coalesces suite writes to disk.
    func publish(
        _ snapshot: BatterySnapshot,
        todayEnergy: EnergyAggregator.DayTotal?,
        smoothedPowerWatts: Double?,
        at date: Date = Date()
    ) {
        guard let defaults else { return }
        let payload = WidgetSnapshot(
            percentage: snapshot.percentage,
            isCharging: snapshot.isCharging,
            isPluggedIn: snapshot.isPluggedIn,
            isFullyCharged: snapshot.isFullyCharged,
            isLowPowerMode: snapshot.isLowPowerMode,
            // Schema v2: macOS Optimized-Charging / policy hold (the panel's
            // "Paused by macOS" state) surfaced to the widgets.
            isChargeHold: snapshot.isPausedByMacOS,
            minutesRemaining: snapshot.minutesRemaining,
            systemPowerWatts: snapshot.systemPowerWatts,
            adapterWatts: snapshot.adapterWatts,
            adapterName: snapshot.adapterName,
            energyTodayWh: todayEnergy?.wattHours,
            energySampledMinutes: todayEnergy?.sampledMinutes,
            energyAvgWatts: smoothedPowerWatts,
            timestamp: date
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.storageKey)
        // Ask WidgetKit to reload timelines; rate-limited by the system, so
        // calling it on every tick is safe (it coalesces under the hood).
        Self.reloadWidgets()
    }

    static let storageKey = "widgetSnapshot"

    /// Best-effort reload request. Rate-limited and coalesced by the system.
    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

#if canImport(WidgetKit)
import WidgetKit
#endif
