import Foundation
import PowerCore

/// Samples battery power on the existing poll cadence and persists per-day
/// energy totals so the panel can show usage history across launches.
///
/// Design follows `DeviceHistoryStore`: pure aggregation logic lives in
/// `PowerCore.EnergyAggregator`; this type only owns the ring buffer of recent
/// samples and JSON persistence.
@MainActor
final class EnergyStore {
    /// In-memory samples kept for integration; older days come from disk.
    /// Two days of samples at a 5s cadence is 34k entries worst case — small,
    /// but we trim aggressively anyway since totals are already persisted.
    private static let sampleRetention: TimeInterval = 48 * 3600
    /// Kept day totals; older ones are pruned on load.
    private static let dayRetention = 30
    private static let flushInterval: TimeInterval = 60

    private let fileURL: URL
    private let calendar: Calendar
    private let now: () -> Date

    private var samples: [EnergyAggregator.Sample] = []
    private var dayTotals: [EnergyAggregator.DayTotal] = []
    private var lastFlush = Date.distantPast

    /// Per-day energy totals (oldest first), including today's in-progress total.
    var dailyTotals: [EnergyAggregator.DayTotal] {
        dayTotals
    }

    init(
        directory: URL? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.calendar = calendar
        self.now = now

        let base = directory ?? Self.defaultDirectory()
        self.fileURL = base.appendingPathComponent("energy-history-v1.json")

        let stored = Self.load(from: fileURL, calendar: calendar, now: now())
        self.dayTotals = stored.totals
        self.samples = stored.samples
    }

    /// Records a power reading. Accumulates into today's total and prunes
    /// stale samples. Flushes to disk at most once per minute.
    func record(powerWatts: Double, at date: Date? = nil) {
        let timestamp = date ?? now()
        samples.append(EnergyAggregator.Sample(date: timestamp, watts: powerWatts))

        let cutoff = timestamp.addingTimeInterval(-Self.sampleRetention)
        if let firstFresh = samples.firstIndex(where: { $0.date >= cutoff }) {
            samples.removeFirst(firstFresh)
        } else if samples.first.map({ $0.date < cutoff }) == true {
            samples.removeAll()
        }

        recomputeTotals()

        if now().timeIntervalSince(lastFlush) >= Self.flushInterval {
            persist()
        }
    }

    /// Today's running total, or `nil` before the second sample of the day.
    var todayTotal: EnergyAggregator.DayTotal? {
        let key = EnergyAggregator.dayKey(for: now(), calendar: calendar)
        return dayTotals.first { $0.dayKey == key }
    }

    /// Forces a disk write (called on app termination).
    func flush() {
        persist()
    }

    // MARK: - Aggregation

    private func recomputeTotals() {
        // Fresh totals from the sample window; persisted history for older days.
        let fresh = EnergyAggregator.dailyTotals(from: samples, calendar: calendar)
        let freshKeys = Set(fresh.map(\.dayKey))
        let historical = dayTotals.filter { !freshKeys.contains($0.dayKey) }
        dayTotals = (historical + fresh).sorted { $0.dayKey < $1.dayKey }

        if dayTotals.count > Self.dayRetention {
            dayTotals.removeFirst(dayTotals.count - Self.dayRetention)
        }
    }

    // MARK: - Persistence

    private struct PersistedHistory: Codable {
        var dayTotals: [EnergyAggregator.DayTotal]
        var samples: [EnergyAggregator.Sample]
    }

    private func persist() {
        let payload = PersistedHistory(dayTotals: dayTotals, samples: samples)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            lastFlush = now()
        } catch {
            // Persistence is best-effort; losing a minute of history is
            // preferable to crashing or blocking the poll loop.
        }
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Voltio", isDirectory: true)
    }

    private static func load(
        from url: URL, calendar: Calendar, now: Date
    ) -> (totals: [EnergyAggregator.DayTotal], samples: [EnergyAggregator.Sample]) {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(PersistedHistory.self, from: data)
        else { return ([], []) }

        // Drop days that fell out of retention while the app was closed.
        let cutoffKey = dayKeyOffset(daysAgo: dayRetention - 1, from: now, calendar: calendar)
        let totals = payload.dayTotals.filter { $0.dayKey >= cutoffKey }
        let cutoff = now.addingTimeInterval(-sampleRetention)
        let samples = payload.samples.filter { $0.date >= cutoff }
        return (totals, samples)
    }

    private static func dayKeyOffset(daysAgo: Int, from date: Date, calendar: Calendar) -> String {
        guard let past = calendar.date(byAdding: .day, value: -daysAgo, to: date) else { return "" }
        return EnergyAggregator.dayKey(for: past, calendar: calendar)
    }
}
