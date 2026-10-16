import SwiftUI
import PowerCore

/// How power is split at this instant, for the flow visualization.
struct PowerFlow {
    /// Live watts entering from the wall adapter (0 when on battery).
    let adapterWatts: Double
    /// The adapter's *rated* wattage, shown as a badge (e.g. "33W"). `nil` on battery.
    let adapterRatedWatts: Int?
    /// Friendly adapter name when available (e.g. "96W USB-C Power Adapter").
    let adapterName: String?
    /// Watts consumed by the system (screen, CPU, etc.).
    let systemWatts: Double
    /// Watts in/out of the battery. Positive = charging, negative = discharging.
    let batteryWatts: Double
    /// Current charge level, for the on-battery source tile.
    let batteryPercent: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let isFullyCharged: Bool
}

/// UI-facing presentation derived from a `BatterySnapshot`.
/// Kept in the app layer so `PowerCore` stays free of SwiftUI.
extension BatterySnapshot {

    var stateColor: Color {
        if isCharging { return .green }
        switch percentage {
        case ...10: return .red
        case ...20: return .orange
        case ...50: return .yellow
        default: return .green
        }
    }

    /// True when macOS itself is holding charge back while the adapter is
    /// connected — Optimized Battery Charging's ~80% hold or an unspecified
    /// system policy hold. Thermal holds and "fully charged" have their own
    /// accurate labels, so they don't count.
    var isPausedByMacOS: Bool {
        guard isPluggedIn, !isCharging, !isFullyCharged else { return false }
        switch notChargingReason {
        case .optimizedChargingHold, .systemHold: return true
        default: return false
        }
    }

    /// One-line description of the native charge-limit configuration, for the
    /// panel's condition area. `nil` when no limit is set — the common case.
    func chargeLimitLabel(limit: ChargeLimitState?) -> String? {
        guard let limit, limit.isEnabled, let percent = limit.percent else { return nil }
        return "macOS Charge Limit: \(percent)%"
    }

    var statusText: String {
        if isPausedByMacOS { return "Paused by macOS" }
        if isFullyCharged { return "Fully charged" }
        if isCharging { return "Charging" }
        if isPluggedIn { return "Plugged in" }
        return "On battery"
    }

    var statusIcon: String {
        if isPausedByMacOS { return "bolt.pause.fill" }
        if isCharging { return "bolt.fill" }
        if isPluggedIn { return "powerplug.fill" }
        return "battery.50percent"
    }

    var healthLabel: String { isHealthGood ? "Good" : "Service recommended" }
    var healthColor: Color { isHealthGood ? .green : .orange }

    /// Whether current is flowing into (charging) or out of (discharging) the battery.
    var currentDirectionIcon: String {
        amperage >= 0 ? "arrow.up" : "arrow.down"
    }

    /// Short verdict on the electrical state shown under the current reading.
    var electricalVerdict: (label: String, color: Color) {
        let flow = isCharging ? "Charging" : (isPluggedIn ? "Not charging" : "Discharging")
        switch voltage {
        case 10.5...13.2: return ("\(flow) · Normal voltage", .green)
        case ..<10.5: return ("\(flow) · Low voltage", .orange)
        default: return ("\(flow) · High voltage", .orange)
        }
    }

    /// Battery pack temperature banding (these are pack temps, not CPU temps).
    var temperatureStatus: (label: String, color: Color) {
        switch temperatureCelsius {
        case ..<35: return ("Normal", .green)
        case ..<42: return ("Warm", .yellow)
        default: return ("Hot", .red)
        }
    }

    /// Menu-bar "charging" affordance (bolt + green). Keyed on the adapter being
    /// connected — which flips *instantly* — rather than the `IsCharging` hardware
    /// flag, which can lag several seconds after plug-in and made the icon feel
    /// sluggish compared with native tools.
    var menuBarCharging: Bool { isPluggedIn }

    /// Menu-bar tint that turns green the instant the adapter connects.
    var menuBarStateColor: Color {
        if isPluggedIn { return .green }
        switch percentage {
        case ...10: return .red
        case ...20: return .orange
        case ...50: return .yellow
        default: return .green
        }
    }

    /// Level-aware SF Symbol for the menu-bar item.
    var menuBarSymbol: String {
        if menuBarCharging { return "battery.100percent.bolt" }
        switch percentage {
        case ...10: return "battery.0percent"
        case ...30: return "battery.25percent"
        case ...55: return "battery.50percent"
        case ...85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var powerFlow: PowerFlow {
        let battery = powerWatts // signed: + charging, - discharging
        if isPluggedIn {
            // Total power drawn from the wall = system load + charge into battery.
            // Fall back to the battery figure if telemetry is unavailable.
            let intoBattery = max(0, battery)
            let adapterInput = systemPowerWatts ?? intoBattery
            let system = max(0, adapterInput - intoBattery)
            return PowerFlow(
                adapterWatts: adapterInput,
                adapterRatedWatts: adapterWatts,
                adapterName: adapterName,
                systemWatts: system,
                batteryWatts: battery,
                batteryPercent: percentage,
                isCharging: isCharging,
                isPluggedIn: true,
                isFullyCharged: isFullyCharged
            )
        } else {
            return PowerFlow(
                adapterWatts: 0,
                adapterRatedWatts: nil,
                adapterName: nil,
                systemWatts: abs(min(0, battery)),
                batteryWatts: battery,
                batteryPercent: percentage,
                isCharging: false,
                isPluggedIn: false,
                isFullyCharged: false
            )
        }
    }
}

enum Format {
    static func watts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    static func minutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }

    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func mAh(_ value: Int) -> String {
        number(value) + " mAh"
    }

    /// Compact "updated" phrasing, e.g. "just now", "2 min ago", "3d ago".
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<10: return "just now"
        case ..<60: return "\(seconds)s ago"
        case ..<3600: return "\(seconds / 60) min ago"
        case ..<86_400: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86_400)d ago"
        }
    }
}

/// App metadata for the footer. Reads from the bundle when packaged as a
/// `.app`, falling back to constants when run as a raw SwiftPM binary.
enum AppInfo {
    static let name = bundleString("CFBundleName") ?? "Voltio"
    static let version = bundleString("CFBundleShortVersionString") ?? "0.1.0"

    private static func bundleString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return nil }
        return value
    }
}
