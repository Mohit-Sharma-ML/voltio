import Foundation

/// An immutable, point-in-time reading of the Mac's internal battery.
///
/// All values originate from the IOKit `AppleSmartBattery` service. Raw register
/// units (centi-degrees, millivolts, etc.) are normalized here into conventional
/// units so the UI layer never deals with hardware encoding quirks.
public struct BatterySnapshot: Sendable, Equatable {
    /// Charge level, 0–100.
    public let percentage: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let isFullyCharged: Bool
    /// macOS Low Power Mode is engaged.
    public let isLowPowerMode: Bool

    /// Minutes until full (when charging) or until empty (when discharging).
    /// `nil` when the system reports an indeterminate estimate.
    public let minutesRemaining: Int?

    public let cycleCount: Int
    public let designCycleCount: Int

    public let temperatureCelsius: Double
    /// Pack voltage in volts.
    public let voltage: Double
    /// Net pack current in milliamps. Positive = into the battery (charging),
    /// negative = out of the battery (discharging).
    public let amperage: Int

    public let currentCapacitymAh: Int
    public let maxCapacitymAh: Int
    public let designCapacitymAh: Int

    public let adapterWatts: Int?
    public let adapterName: String?

    /// Instantaneous power drawn by the whole system, in watts.
    public let systemPowerWatts: Double?
    /// Instantaneous power flowing in/out of the battery, in watts.
    public let batteryPowerWatts: Double?

    /// Why the system is plugged in but not charging (Optimized Battery
    /// Charging, heat, hold at 80%, …). `nil` when charging normally or on
    /// battery power.
    public let notChargingReason: NotChargingReason?

    /// Battery pack serial number as reported by the firmware.
    public let serialNumber: String?

    /// Firmware-reported manufacture date, when decodable.
    public let manufactureDate: Date?

    public init(
        percentage: Int,
        isCharging: Bool,
        isPluggedIn: Bool,
        isFullyCharged: Bool,
        isLowPowerMode: Bool = false,
        minutesRemaining: Int?,
        cycleCount: Int,
        designCycleCount: Int,
        temperatureCelsius: Double,
        voltage: Double,
        amperage: Int,
        currentCapacitymAh: Int,
        maxCapacitymAh: Int,
        designCapacitymAh: Int,
        adapterWatts: Int?,
        adapterName: String?,
        systemPowerWatts: Double?,
        batteryPowerWatts: Double?,
        notChargingReason: NotChargingReason? = nil,
        serialNumber: String? = nil,
        manufactureDate: Date? = nil
    ) {
        self.percentage = percentage
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isFullyCharged = isFullyCharged
        self.isLowPowerMode = isLowPowerMode
        self.minutesRemaining = minutesRemaining
        self.cycleCount = cycleCount
        self.designCycleCount = designCycleCount
        self.temperatureCelsius = temperatureCelsius
        self.voltage = voltage
        self.amperage = amperage
        self.currentCapacitymAh = currentCapacitymAh
        self.maxCapacitymAh = maxCapacitymAh
        self.designCapacitymAh = designCapacitymAh
        self.adapterWatts = adapterWatts
        self.adapterName = adapterName
        self.systemPowerWatts = systemPowerWatts
        self.batteryPowerWatts = batteryPowerWatts
        self.notChargingReason = notChargingReason
        self.serialNumber = serialNumber
        self.manufactureDate = manufactureDate
    }

    /// Battery health as a whole percentage of original (design) capacity.
    /// Uses integer flooring to match how macOS battery tools present the value.
    public var healthPercent: Int {
        guard designCapacitymAh > 0 else { return 0 }
        return maxCapacitymAh * 100 / designCapacitymAh
    }

    public var temperatureFahrenheit: Double {
        temperatureCelsius * 9.0 / 5.0 + 32.0
    }

    /// Net battery power in watts, derived from pack voltage × current.
    /// Positive = charging into the battery, negative = discharging.
    /// Always available, unlike `systemPowerWatts` (adapter input, zero on battery).
    public var powerWatts: Double {
        voltage * Double(amperage) / 1000.0
    }

    /// Apple's service guidance threshold: below 80% health is "Service recommended".
    public var isHealthGood: Bool { healthPercent >= 80 }

    /// A copy of this snapshot with the percentage replaced. Used by Developer
    /// Mode to simulate battery levels without patching IOKit.
    public func overridingPercentage(_ percent: Int) -> BatterySnapshot {
        BatterySnapshot(
            percentage: max(0, min(100, percent)),
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isFullyCharged: isFullyCharged,
            isLowPowerMode: isLowPowerMode,
            minutesRemaining: minutesRemaining,
            cycleCount: cycleCount,
            designCycleCount: designCycleCount,
            temperatureCelsius: temperatureCelsius,
            voltage: voltage,
            amperage: amperage,
            currentCapacitymAh: currentCapacitymAh,
            maxCapacitymAh: maxCapacitymAh,
            designCapacitymAh: designCapacitymAh,
            adapterWatts: adapterWatts,
            adapterName: adapterName,
            systemPowerWatts: systemPowerWatts,
            batteryPowerWatts: batteryPowerWatts,
            notChargingReason: notChargingReason,
            serialNumber: serialNumber,
            manufactureDate: manufactureDate
        )
    }

    /// Why a plugged-in battery isn't charging. Derived from IOKit charge
    /// flags rather than a single registry key, since macOS encodes this as a
    /// combination of `FullyCharged`, `ChargingWhilePluggedIn`-style bits and
    /// optimized-charging state.
    public enum NotChargingReason: Sendable, Equatable {
        /// Battery reached full — nothing to charge.
        case fullyCharged
        /// macOS Optimized Battery Charging is holding charge (usually ~80%).
        case optimizedChargingHold
        /// Battery or adapter temperature outside the safe charging window.
        case temperatureHold
        /// Charge level held by system policy for an unknown reason.
        case systemHold

        /// Human-readable explanation used by the panel's condition card.
        public var explanation: String {
            switch self {
            case .fullyCharged: return "battery is fully charged"
            case .optimizedChargingHold: return "Optimized Charging is holding the level"
            case .temperatureHold: return "temperature is outside the charging range"
            case .systemHold: return "the system is holding the charge level"
            }
        }
    }
}
