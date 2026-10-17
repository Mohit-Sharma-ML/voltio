import Foundation
import IOKit

public enum BatteryReaderError: Error, Sendable {
    /// No internal battery was found (e.g. a desktop Mac).
    case serviceNotFound
    /// The IOKit service exists but its properties could not be read.
    case propertiesUnavailable
}

/// Reads the Mac's internal battery state from the IOKit `AppleSmartBattery`
/// service. Stateless and cheap to construct; `read()` performs one registry query.
public struct BatteryReader: Sendable {
    public init() {}

    public func read() throws -> BatterySnapshot {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { throw BatteryReaderError.serviceNotFound }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else {
            throw BatteryReaderError.propertiesUnavailable
        }

        return BatteryReader.parse(dictionary)
    }

    /// Maps a raw `AppleSmartBattery` property dictionary into a normalized snapshot.
    /// Pure and side-effect free so it can be unit-tested with captured fixtures.
    public static func parse(_ d: [String: Any]) -> BatterySnapshot {
        // IOKit stores some currents as unsigned 64-bit values that are actually
        // two's-complement negatives. `int64Value` reinterprets the bit pattern
        // correctly (e.g. 0xFFFF…FFCA -> -54).
        let isCharging = boolValue(d["IsCharging"]) ?? false
        let isPluggedIn = boolValue(d["ExternalConnected"]) ?? false
        let isFullyCharged = boolValue(d["FullyCharged"]) ?? false

        let adapter = d["AdapterDetails"] as? [String: Any]
        let telemetry = d["PowerTelemetryData"] as? [String: Any]

        return BatterySnapshot(
            percentage: intValue(d["CurrentCapacity"]) ?? 0,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isFullyCharged: isFullyCharged,
            isLowPowerMode: boolValue(d["IsLowPowerMode"]) ?? false,
            minutesRemaining: timeEstimate(d, isCharging: isCharging),
            cycleCount: intValue(d["CycleCount"]) ?? 0,
            designCycleCount: intValue(d["DesignCycleCount9C"]) ?? 0,
            temperatureCelsius: Double(intValue(d["Temperature"]) ?? 0) / 100.0,
            voltage: Double(intValue(d["Voltage"]) ?? 0) / 1000.0,
            amperage: Int(int64Value(d["Amperage"]) ?? int64Value(d["InstantAmperage"]) ?? 0),
            currentCapacitymAh: intValue(d["AppleRawCurrentCapacity"]) ?? 0,
            maxCapacitymAh: intValue(d["AppleRawMaxCapacity"]) ?? 0,
            designCapacitymAh: intValue(d["DesignCapacity"]) ?? 0,
            adapterWatts: intValue(adapter?["Watts"]),
            adapterName: (adapter?["Name"] as? String)?.trimmingCharacters(in: .whitespaces),
            systemPowerWatts: milliWattsToWatts(telemetry?["SystemPowerIn"]),
            batteryPowerWatts: milliWattsToWatts(telemetry?["BatteryPower"]),
            notChargingReason: notChargingReason(
                d, isCharging: isCharging, isPluggedIn: isPluggedIn, isFullyCharged: isFullyCharged
            ),
            serialNumber: d["BatterySerialNumber"] as? String,
            manufactureDate: manufactureDate(d)
        )
    }

    // MARK: - Field helpers

    private static func timeEstimate(_ d: [String: Any], isCharging: Bool) -> Int? {
        let primaryKey = isCharging ? "AvgTimeToFull" : "AvgTimeToEmpty"
        for key in [primaryKey, "TimeRemaining"] {
            if let value = intValue(d[key]), isValidEstimate(value) {
                return value
            }
        }
        return nil
    }

    /// 0xFFFF is AppleSmartBattery's sentinel for "no valid estimate".
    private static let invalidTimeEstimate = 65535
    /// IOKit also emits *garbage* non-sentinel estimates when no estimate is
    /// meaningful — e.g. `AvgTimeToEmpty` ≈ 40,000 minutes (27+ days) while
    /// fully charged on AC (observed 2026-10-17: the panel showed
    /// "277h 21m remaining" at 100% / "Fully charged"). No laptop pack
    /// discharges over 24 h, so anything beyond that is treated as
    /// "no estimate" rather than displayed.
    private static let maxPlausibleEstimateMinutes = 24 * 60

    private static func isValidEstimate(_ minutes: Int) -> Bool {
        minutes > 0 && minutes != invalidTimeEstimate && minutes <= maxPlausibleEstimateMinutes
    }

    private static func milliWattsToWatts(_ value: Any?) -> Double? {
        guard let mw = int64Value(value) else { return nil }
        return Double(mw) / 1000.0
    }

    private static func intValue(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        return value as? Bool
    }

    /// Derives why a plugged-in pack isn't charging. macOS doesn't expose a
    /// single "reason" key, so combine the status flags Apple does publish:
    /// - `FullyCharged`: pack is at capacity.
    /// - `ChargeStatus`/`BatteryHealthData` hold bits on newer macOS.
    /// - Optimized Battery Charging surfaces as charging being inhibited
    ///   while `ExternalConnected` is true and capacity is below 100%.
    private static func notChargingReason(
        _ d: [String: Any],
        isCharging: Bool,
        isPluggedIn: Bool,
        isFullyCharged: Bool
    ) -> BatterySnapshot.NotChargingReason? {
        guard isPluggedIn, !isCharging else { return nil }

        if isFullyCharged { return .fullyCharged }

        // "ChargeInhibited" is the flag IOKit sets when Optimized Battery
        // Charging (or thermal policy) pauses charging on newer macOS.
        if boolValue(d["ChargeInhibited"]) == true {
            return temperatureHoldCheck(d) ?? .optimizedChargingHold
        }

        // Legacy macOS exposed an explicit hold-at-capacity state.
        if let status = intValue(d["ChargeStatus"]), status == 2 {
            return .systemHold
        }

        return .optimizedChargingHold
    }

    /// Distinguishes a thermal hold from a software hold by checking the
    /// pack temperature against Apple's documented charging window.
    private static func temperatureHoldCheck(_ d: [String: Any]) -> BatterySnapshot.NotChargingReason? {
        let temp = Double(intValue(d["Temperature"]) ?? 0) / 100.0
        // Apple charges between roughly 0°C and 45°C; outside that, hold.
        if temp >= 45.0 || (temp > 0 && temp <= 1.0) { return .temperatureHold }
        return nil
    }

    /// Apple encodes the pack's manufacture date as a packed 16-bit value:
    /// bits 15–9 = year offset from 1980, bits 8–5 = month, bits 4–0 = day.
    /// Newer firmware instead stores an ISO-ish string in
    /// `BatteryData`/`ManufactureDate`. Prefer the string when present.
    private static func manufactureDate(_ d: [String: Any]) -> Date? {
        if let string = d["ManufactureDate"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter.date(from: string)
        }

        guard let packed = intValue(d["ManufactureDate"]) else { return nil }
        let year = 1980 + ((packed >> 9) & 0x7F)
        let month = (packed >> 5) & 0x0F
        let day = packed & 0x1F
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(from: components)
    }
}
