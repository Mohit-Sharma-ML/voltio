import Foundation

/// The payload the Voltio app hands to the widget extension through the App
/// Group UserDefaults suite.
///
/// Deliberately a *flattened subset* of `BatterySnapshot` plus today's energy
/// figure: widgets need a small, `Codable`, forward-compatible struct, not the
/// full snapshot. Unknown fields are ignored on decode (widget built against an
/// older/newer app still works), so field removals are the only breaking change.
///
/// The writer publishes on every battery tick; the widget reads on timeline
/// construction. No live IPC — the widget is a snapshot viewer by design, since
/// WidgetKit only lets a widget render on the timeline it returned.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    // MARK: - Schema

    /// v2 (2026-10-16): added `isChargeHold` (macOS Optimized Charging /
    /// policy hold). Decode stays backward compatible: v1 payloads (missing
    /// the field) decode with `isChargeHold == false`.
    public static let schemaVersion: Int = 2

    // MARK: - Battery

    public let percentage: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let isFullyCharged: Bool
    public let isLowPowerMode: Bool
    /// macOS is holding the charge while plugged in (Optimized Battery
    /// Charging near ~80%, or a system policy hold) — the widget shows a
    /// hold badge instead of treating "plugged, not charging" as anomalous.
    /// Schema v2; absent in v1 payloads (decodes as `false`).
    public let isChargeHold: Bool
    /// Minutes until full (charging) or empty (discharging). `nil` when the
    /// system estimate is indeterminate.
    public let minutesRemaining: Int?

    // MARK: - Power

    /// Whole-system draw in watts (nil when the hardware doesn't report it).
    public let systemPowerWatts: Double?
    public let adapterWatts: Int?
    public let adapterName: String?

    // MARK: - Energy today (from EnergyStore)

    public let energyTodayWh: Double?
    public let energySampledMinutes: Double?
    /// Smoothed average draw over the sampling window, in watts.
    public let energyAvgWatts: Double?

    // MARK: - Freshness

    /// When the app wrote this payload. The widget shows a "stale" cue when the
    /// app hasn't run recently (Voltio quit, or the Mac slept).
    public let timestamp: Date

    public init(
        percentage: Int,
        isCharging: Bool,
        isPluggedIn: Bool,
        isFullyCharged: Bool,
        isLowPowerMode: Bool,
        isChargeHold: Bool = false,
        minutesRemaining: Int?,
        systemPowerWatts: Double?,
        adapterWatts: Int?,
        adapterName: String?,
        energyTodayWh: Double?,
        energySampledMinutes: Double?,
        energyAvgWatts: Double?,
        timestamp: Date
    ) {
        self.percentage = percentage
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isFullyCharged = isFullyCharged
        self.isLowPowerMode = isLowPowerMode
        self.isChargeHold = isChargeHold
        self.minutesRemaining = minutesRemaining
        self.systemPowerWatts = systemPowerWatts
        self.adapterWatts = adapterWatts
        self.adapterName = adapterName
        self.energyTodayWh = energyTodayWh
        self.energySampledMinutes = energySampledMinutes
        self.energyAvgWatts = energyAvgWatts
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case percentage, isCharging, isPluggedIn, isFullyCharged
        case isLowPowerMode, isChargeHold, minutesRemaining
        case systemPowerWatts, adapterWatts, adapterName
        case energyTodayWh, energySampledMinutes, energyAvgWatts, timestamp
    }

    /// Backward-compatible decode: `isChargeHold` was added in schema v2, so
    /// v1 payloads (written by an older app) lack the key — default it to
    /// `false` instead of failing the decode. All other fields remain
    /// required (the writer always emits them).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        percentage = try container.decode(Int.self, forKey: .percentage)
        isCharging = try container.decode(Bool.self, forKey: .isCharging)
        isPluggedIn = try container.decode(Bool.self, forKey: .isPluggedIn)
        isFullyCharged = try container.decode(Bool.self, forKey: .isFullyCharged)
        isLowPowerMode = try container.decode(Bool.self, forKey: .isLowPowerMode)
        isChargeHold = try container.decodeIfPresent(Bool.self, forKey: .isChargeHold) ?? false
        minutesRemaining = try container.decodeIfPresent(Int.self, forKey: .minutesRemaining)
        systemPowerWatts = try container.decodeIfPresent(Double.self, forKey: .systemPowerWatts)
        adapterWatts = try container.decodeIfPresent(Int.self, forKey: .adapterWatts)
        adapterName = try container.decodeIfPresent(String.self, forKey: .adapterName)
        energyTodayWh = try container.decodeIfPresent(Double.self, forKey: .energyTodayWh)
        energySampledMinutes = try container.decodeIfPresent(Double.self, forKey: .energySampledMinutes)
        energyAvgWatts = try container.decodeIfPresent(Double.self, forKey: .energyAvgWatts)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    // MARK: - Presentation helpers (shared by widget and tests)

    /// Short status line: "Charging", "Charging Paused", "Plugged In",
    /// "Low Power", "On Battery".
    public var statusText: String {
        if isPluggedIn {
            if isCharging { return "Charging" }
            if isFullyCharged { return "Fully Charged" }
            if isChargeHold { return "Charging Paused" }
            return "Plugged In"
        }
        return isLowPowerMode ? "Low Power Mode" : "On Battery"
    }

    /// "1 h 05 m left", "42 m left", or nil when unknown.
    public var timeRemainingText: String? {
        guard let minutes = minutesRemaining, minutes > 0 else { return nil }
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 {
            return m > 0 ? "\(h) h \(String(format: "%02d", m)) m left" : "\(h) h left"
        }
        return "\(m) m left"
    }
}
