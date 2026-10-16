import Foundation

/// Pure logic for turning periodic battery-power samples into per-day energy
/// totals. Kept storage-free (matching `DeviceHistory`) so the app layer owns
/// persistence and this stays unit-testable.
public enum EnergyAggregator {
    /// One battery-power reading taken at a point in time (watts).
    public struct Sample: Sendable, Equatable, Codable {
        public let date: Date
        public let watts: Double

        public init(date: Date, watts: Double) {
            self.date = date
            self.watts = watts
        }
    }

    /// Energy used during one calendar day, in watt-hours.
    public struct DayTotal: Sendable, Equatable, Codable, Identifiable {
        /// Day bucket as `yyyy-MM-dd` in the user's calendar.
        public let dayKey: String
        public let wattHours: Double
        /// Minutes of the day actually sampled — lets the UI distinguish
        /// "quiet day" from "laptop was asleep all day".
        public let sampledMinutes: Double

        public var id: String { dayKey }

        public init(dayKey: String, wattHours: Double, sampledMinutes: Double) {
            self.dayKey = dayKey
            self.wattHours = wattHours
            self.sampledMinutes = sampledMinutes
        }

        /// Energy in kilowatt-hours, the unit people see on utility bills.
        public var kilowattHours: Double { wattHours / 1000.0 }
    }

    /// `yyyy-MM-dd` bucket key for a date in the given calendar/timezone.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            comps.year ?? 0, comps.month ?? 0, comps.day ?? 0
        )
    }

    /// Integrates consecutive samples with the trapezoid rule: each pair
    /// contributes `averagePower × elapsedHours`. Samples spanning a day
    /// boundary are split so each day gets its share. Gaps longer than
    /// `maxGap` (sleep, app not running) contribute nothing — otherwise an
    /// overnight gap would silently bill yesterday's last reading to today.
    public static func dailyTotals(
        from samples: [Sample],
        maxGap: TimeInterval = 10 * 60,
        calendar: Calendar = .current
    ) -> [DayTotal] {
        guard samples.count >= 2 else { return [] }

        var totals: [String: (wh: Double, minutes: Double)] = [:]

        for i in 1..<samples.count {
            let previous = samples[i - 1]
            let current = samples[i]
            let interval = current.date.timeIntervalSince(previous.date)
            guard interval > 0, interval <= maxGap else { continue }

            // Trapezoid: average of the two endpoint powers over the interval.
            let averageWatts = (previous.watts + current.watts) / 2.0

            // Attribute the interval to the day each portion belongs in.
            var cursor = previous.date
            let hoursPerSecond = 1.0 / 3600.0
            while cursor < current.date {
                let dayEnd = endOfDay(cursor, calendar: calendar)
                let segmentEnd = min(dayEnd, current.date)
                let segment = segmentEnd.timeIntervalSince(cursor)
                guard segment > 0 else { break }

                let key = dayKey(for: cursor, calendar: calendar)
                let wh = averageWatts * Double(segment) * hoursPerSecond
                let existing = totals[key] ?? (0, 0)
                totals[key] = (existing.wh + wh, existing.minutes + segment / 60.0)
                cursor = segmentEnd
            }
        }

        return totals
            .map { DayTotal(dayKey: $0.key, wattHours: $0.value.wh, sampledMinutes: $0.value.minutes) }
            .sorted { $0.dayKey < $1.dayKey }
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date
    }
}
