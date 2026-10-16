import PowerCore
import WidgetKit

/// Reads the snapshot the app published to the App Group suite. All access is
/// synchronous JSON decode — safe to call from the timeline provider.
enum WidgetSnapshotReader {
    /// Must match WidgetSnapshotWriter.appGroupID and both entitlements files.
    /// Team-ID prefix required — see AppGroupConfiguration (injected at build time).
    static let appGroupID = AppGroupConfiguration.appGroupID
    static let storageKey = "widgetSnapshot"

    /// Returns the newest payload, or nil when the app never wrote (fresh
    /// install, widget added before first app launch) or the suite is missing.
    static func read(defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)) -> WidgetSnapshot? {
        guard let defaults, let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

/// Timeline strategy: one entry now, refreshed in 15 minutes. The app calls
/// `WidgetCenter.reloadAllTimelines()` on every battery tick, so in practice the
/// widget updates within seconds of the app running; the 15-minute fallback
/// covers the case where Voltio isn't running (sleep, quit) and keeps the
/// "last updated" label roughly honest.
struct VoltioTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(
            snapshot: WidgetSnapshot(
                percentage: 76,
                isCharging: false,
                isPluggedIn: false,
                isFullyCharged: false,
                isLowPowerMode: false,
                minutesRemaining: 230,
                systemPowerWatts: 12.4,
                adapterWatts: nil,
                adapterName: nil,
                energyTodayWh: 18.2,
                energySampledMinutes: 96,
                energyAvgWatts: 11.9,
                timestamp: Date()
            ),
            date: Date()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(BatteryEntry(snapshot: WidgetSnapshotReader.read(), date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let now = Date()
        let entry = BatteryEntry(snapshot: WidgetSnapshotReader.read(), date: now)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

struct BatteryEntry: TimelineEntry {
    /// nil when the app hasn't published anything yet — views render a
    /// "waiting for Voltio" placeholder in that case.
    let snapshot: WidgetSnapshot?
    let date: Date
}
