import XCTest
@testable import PowerCore

final class EnergyAggregatorTests: XCTestCase {
    /// Fixed GMT+0 calendar so day-boundary tests are deterministic regardless
    /// of the machine running the suite.
    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        // Accept date-only strings ("2025-03-05") as midnight.
        let text = iso.contains("T") ? iso : "\(iso)T00:00"
        guard let parsed = f.date(from: text) else {
            fatalError("bad test date: \(iso)")
        }
        return parsed
    }

    // MARK: - dayKey

    func testDayKeyFormat() {
        XCTAssertEqual(
            EnergyAggregator.dayKey(for: date("2025-03-05"), calendar: utcCalendar),
            "2025-03-05"
        )
        // Zero-padded single digits.
        XCTAssertEqual(
            EnergyAggregator.dayKey(for: date("2025-01-09"), calendar: utcCalendar),
            "2025-01-09"
        )
    }

    // MARK: - dailyTotals

    func testTooFewSamplesYieldNothing() {
        XCTAssertTrue(EnergyAggregator.dailyTotals(from: [], calendar: utcCalendar).isEmpty)
        let one = [EnergyAggregator.Sample(date: date("2025-03-05"), watts: 10)]
        XCTAssertTrue(EnergyAggregator.dailyTotals(from: one, calendar: utcCalendar).isEmpty)
    }

    func testSingleIntervalTrapezoid() {
        // 10 W for 1 hour starting 10:00.
        let samples = [
            EnergyAggregator.Sample(date: date("2025-03-05T10:00"), watts: 10),
            EnergyAggregator.Sample(date: date("2025-03-05T11:00"), watts: 10),
        ]
        let totals = EnergyAggregator.dailyTotals(
            from: samples, maxGap: 2 * 60 * 60, calendar: utcCalendar
        )

        guard totals.count == 1 else {
            return XCTFail("expected 1 day total, got \(totals.count)")
        }
        XCTAssertEqual(totals[0].dayKey, "2025-03-05")
        XCTAssertEqual(totals[0].wattHours, 10.0, accuracy: 0.0001) // 10 W × 1 h
        XCTAssertEqual(totals[0].sampledMinutes, 60.0, accuracy: 0.0001)
        XCTAssertEqual(totals[0].kilowattHours, 0.01, accuracy: 0.00001)
    }

    func testTrapezoidAveragesEndpoints() {
        // 0 W → 6 W over 1 h: average 3 W → 3 Wh.
        let samples = [
            EnergyAggregator.Sample(date: date("2025-03-05T10:00"), watts: 0),
            EnergyAggregator.Sample(date: date("2025-03-05T11:00"), watts: 6),
        ]
        let totals = EnergyAggregator.dailyTotals(
            from: samples, maxGap: 2 * 60 * 60, calendar: utcCalendar
        )
        XCTAssertEqual(totals[0].wattHours, 3.0, accuracy: 0.0001)
    }

    func testGapLongerThanMaxGapContributesNothing() {
        let samples = [
            EnergyAggregator.Sample(date: date("2025-03-05T10:00"), watts: 10),
            EnergyAggregator.Sample(date: date("2025-03-05T20:00"), watts: 10), // 10 h gap
        ]
        let totals = EnergyAggregator.dailyTotals(from: samples, maxGap: 10 * 60, calendar: utcCalendar)
        XCTAssertTrue(totals.isEmpty)
    }

    func testGapJustInsideMaxGapIsCounted() {
        let samples = [
            EnergyAggregator.Sample(date: date("2025-03-05T10:00"), watts: 10),
            EnergyAggregator.Sample(date: date("2025-03-05T10:09"), watts: 10), // 9 min
        ]
        let totals = EnergyAggregator.dailyTotals(from: samples, maxGap: 10 * 60, calendar: utcCalendar)
        XCTAssertEqual(totals[0].wattHours, 1.5, accuracy: 0.0001) // 10 W × 0.15 h
    }

    func testDayBoundarySplitsInterval() {
        // 30 min either side of midnight: 15 Wh per day at a constant 30 W.
        // The full interval is 1 h, so raise maxGap above it — gap filtering
        // is covered by its own tests; this one only exercises day splitting.
        let samples = [
            EnergyAggregator.Sample(date: date("2025-03-05T23:30"), watts: 30),
            EnergyAggregator.Sample(date: date("2025-03-06T00:30"), watts: 30),
        ]
        let totals = EnergyAggregator.dailyTotals(
            from: samples, maxGap: 2 * 60 * 60, calendar: utcCalendar
        )

        guard totals.count == 2 else {
            return XCTFail("expected 2 day totals, got \(totals.count)")
        }
        XCTAssertEqual(totals[0].dayKey, "2025-03-05")
        XCTAssertEqual(totals[0].wattHours, 15.0, accuracy: 0.0001)
        XCTAssertEqual(totals[0].sampledMinutes, 30.0, accuracy: 0.0001)
        XCTAssertEqual(totals[1].dayKey, "2025-03-06")
        XCTAssertEqual(totals[1].wattHours, 15.0, accuracy: 0.0001)
        XCTAssertEqual(totals[1].sampledMinutes, 30.0, accuracy: 0.0001)
    }

    func testNegativeTimeIntervalsAreIgnored() {
        let samples = [
            EnergyAggregator.Sample(date: date("2025-03-05T11:00"), watts: 10),
            EnergyAggregator.Sample(date: date("2025-03-05T10:00"), watts: 10), // out of order
        ]
        XCTAssertTrue(EnergyAggregator.dailyTotals(from: samples, calendar: utcCalendar).isEmpty)
    }

    func testTotalsSortedByDayKey() {
        // 5-minute gaps (within default maxGap) across two days.
        let samples = [
            EnergyAggregator.Sample(date: date("2025-03-07T10:00"), watts: 10),
            EnergyAggregator.Sample(date: date("2025-03-07T10:05"), watts: 10),
            EnergyAggregator.Sample(date: date("2025-03-06T10:00"), watts: 10),
            EnergyAggregator.Sample(date: date("2025-03-06T10:05"), watts: 10),
        ]
        let totals = EnergyAggregator.dailyTotals(from: samples, calendar: utcCalendar)
        XCTAssertEqual(totals.map(\.dayKey), ["2025-03-06", "2025-03-07"])
    }
}
