import XCTest
@testable import PowerCore

final class EnergyAppTrackerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func reading(
        _ pid: pid_t, app: String, name: String? = nil,
        nj: UInt64, cpu: Double
    ) -> EnergyAppTracker.Reading {
        EnergyAppTracker.Reading(
            pid: pid, appID: app, name: name ?? app,
            energyNJ: nj, cpuSeconds: cpu
        )
    }

    // MARK: - Baseline tick

    func testFirstTickProducesNoUsage() {
        let state = EnergyAppTracker.makeState()
        let result = EnergyAppTracker.process(
            [reading(100, app: "Safari", nj: 1_000, cpu: 1)],
            at: t0, systemWatts: 10, state: state
        )
        XCTAssertTrue(result.usage.isEmpty)
        XCTAssertTrue(result.measuredEnergy)
    }

    // MARK: - Energy-counter path

    func testEnergyDeltaToWatts() {
        let state = EnergyAppTracker.makeState()
        // Baseline.
        _ = EnergyAppTracker.process(
            [reading(100, app: "Safari", nj: 0, cpu: 0)],
            at: t0, systemWatts: nil, state: state
        )

        // 5 W for exactly 10 s = 50 J = 50e9 nJ.
        let result = EnergyAppTracker.process(
            [reading(100, app: "Safari", nj: 50_000_000_000, cpu: 0)],
            at: t0.addingTimeInterval(10), systemWatts: nil, state: state
        )

        XCTAssertEqual(result.usage.count, 1)
        XCTAssertEqual(result.usage.first?.appID, "Safari")
        XCTAssertEqual(result.usage.first?.watts ?? 0, 5.0, accuracy: 1e-9)
        XCTAssertEqual(result.usage.first?.method, .energyCounters)
        XCTAssertTrue(result.measuredEnergy)
    }

    func testEnergyDeltaRolledUpAcrossProcesses() {
        let state = EnergyAppTracker.makeState()
        _ = EnergyAppTracker.process(
            [
                reading(100, app: "Safari", nj: 0, cpu: 0),
                reading(101, app: "Safari", nj: 0, cpu: 0),
            ],
            at: t0, systemWatts: nil, state: state
        )

        // Two helper processes of one app: 2 W + 3 W over 10 s.
        let result = EnergyAppTracker.process(
            [
                reading(100, app: "Safari", nj: 20_000_000_000, cpu: 0),
                reading(101, app: "Safari", nj: 30_000_000_000, cpu: 0),
            ],
            at: t0.addingTimeInterval(10), systemWatts: nil, state: state
        )

        XCTAssertEqual(result.usage.count, 1)
        XCTAssertEqual(result.usage.first?.watts ?? 0, 5.0, accuracy: 1e-9)
        XCTAssertEqual(result.usage.first?.processCount, 2)
    }

    func testEnergyCounterResetClampsToZero() {
        let state = EnergyAppTracker.makeState()
        _ = EnergyAppTracker.process(
            [reading(100, app: "Safari", nj: 1_000, cpu: 0)],
            at: t0, systemWatts: nil, state: state
        )
        // Counter went backwards — clamp, don't go negative.
        let result = EnergyAppTracker.process(
            [reading(100, app: "Safari", nj: 500, cpu: 0)],
            at: t0.addingTimeInterval(10), systemWatts: nil, state: state
        )
        // The clamped 0 W draw sits below the visibility threshold, so no
        // entry is emitted; the guarantee is it never goes negative.
        XCTAssertTrue(result.usage.isEmpty)
        // The baseline must reflect the current (lower) counter so a later
        // delta is measured from it, not from the stale higher value.
        XCTAssertEqual(state.pids[100]?.lastEnergyNJ, 500)
    }

    // MARK: - CPU-share fallback

    func testCPUShareFallbackDistributesSystemWatts() {
        let state = EnergyAppTracker.makeState()
        _ = EnergyAppTracker.process(
            [
                reading(1, app: "Busy", nj: 0, cpu: 0),
                reading(2, app: "Idle", nj: 0, cpu: 0),
            ],
            at: t0, systemWatts: nil, state: state
        )

        // Busy burned 3 s of CPU, Idle 1 s, over a 10 s tick.
        let result = EnergyAppTracker.process(
            [
                reading(1, app: "Busy", nj: 0, cpu: 3),
                reading(2, app: "Idle", nj: 0, cpu: 1),
            ],
            at: t0.addingTimeInterval(10), systemWatts: 20, state: state
        )

        XCTAssertEqual(result.usage.count, 2)
        XCTAssertEqual(result.usage.first?.appID, "Busy")
        XCTAssertEqual(result.usage.first?.watts ?? 0, 15, accuracy: 1e-9)
        XCTAssertEqual(result.usage.last?.watts ?? 0, 5, accuracy: 1e-9)
        XCTAssertEqual(result.usage.first?.method, .cpuShare)
        XCTAssertFalse(result.measuredEnergy)
    }

    func testFallbackWithoutSystemWattsYieldsNothing() {
        let state = EnergyAppTracker.makeState()
        _ = EnergyAppTracker.process(
            [reading(1, app: "Busy", nj: 0, cpu: 0)],
            at: t0, systemWatts: nil, state: state
        )
        let result = EnergyAppTracker.process(
            [reading(1, app: "Busy", nj: 0, cpu: 5)],
            at: t0.addingTimeInterval(10), systemWatts: nil, state: state
        )
        XCTAssertTrue(result.usage.isEmpty)
    }

    func testFallbackWithZeroTotalCPUYieldsNothing() {
        let state = EnergyAppTracker.makeState()
        _ = EnergyAppTracker.process(
            [reading(1, app: "Sleepy", nj: 0, cpu: 0)],
            at: t0, systemWatts: 15, state: state
        )
        let result = EnergyAppTracker.process(
            [reading(1, app: "Sleepy", nj: 0, cpu: 0)],
            at: t0.addingTimeInterval(10), systemWatts: 15, state: state
        )
        XCTAssertTrue(result.usage.isEmpty)
    }

    // MARK: - Filtering & ordering

    func testNegligibleDrawsFilteredAndSortedDescending() {
        let state = EnergyAppTracker.makeState()
        _ = EnergyAppTracker.process(
            [
                reading(1, app: "Big", nj: 0, cpu: 0),
                reading(2, app: "Mid", nj: 0, cpu: 0),
                reading(3, app: "Tiny", nj: 0, cpu: 0),
            ],
            at: t0, systemWatts: nil, state: state
        )
        // Over 10 s: Tiny = 0.04 W (below the 0.05 W floor), Mid = 1 W,
        // Big = 10 W.
        let result = EnergyAppTracker.process(
            [
                reading(1, app: "Big", nj: 0, cpu: 10),
                reading(2, app: "Mid", nj: 0, cpu: 1),
                reading(3, app: "Tiny", nj: 0, cpu: 0.04),
            ],
            at: t0.addingTimeInterval(10), systemWatts: 11.04, state: state
        )

        XCTAssertEqual(result.usage.map(\.appID), ["Big", "Mid"])
        XCTAssertGreaterThan(result.usage[0].watts, result.usage[1].watts)
    }

    // MARK: - Robustness

    func testNewPIDWithoutBaselineIsSkippedThenSeeded() {
        let state = EnergyAppTracker.makeState()
        _ = EnergyAppTracker.process(
            [reading(1, app: "App", nj: 0, cpu: 0)],
            at: t0, systemWatts: nil, state: state
        )
        // PID 2 appears mid-stream — no baseline, must be skipped (not
        // attributed from zero and not crashy), but seeded for next tick.
        let mid = EnergyAppTracker.process(
            [
                reading(1, app: "App", nj: 10_000_000_000, cpu: 0),
                reading(2, app: "New", nj: 99_000_000_000, cpu: 0),
            ],
            at: t0.addingTimeInterval(10), systemWatts: nil, state: state
        )
        XCTAssertEqual(mid.usage.map(\.appID), ["App"])

        let next = EnergyAppTracker.process(
            [reading(2, app: "New", nj: 109_000_000_000, cpu: 0)],
            at: t0.addingTimeInterval(20), systemWatts: nil, state: state
        )
        XCTAssertEqual(next.usage.first?.appID, "New")
        XCTAssertEqual(next.usage.first?.watts ?? 0, 1.0, accuracy: 1e-9)
    }

    func testClockJumpSkipsTickAndReseeds() {
        let state = EnergyAppTracker.makeState()
        _ = EnergyAppTracker.process(
            [reading(1, app: "App", nj: 0, cpu: 0)],
            at: t0, systemWatts: nil, state: state
        )
        // Wake-from-sleep style jump: far more than the 60 s sanity ceiling.
        let jumped = EnergyAppTracker.process(
            [reading(1, app: "App", nj: 999_000_000_000, cpu: 0)],
            at: t0.addingTimeInterval(600), systemWatts: nil, state: state
        )
        XCTAssertTrue(jumped.usage.isEmpty)

        // And the very next normal tick works again. Reseed at the skipped
        // tick was 999e9 nJ, so a 5e9 nJ delta over 10 s is 0.5 W.
        let next = EnergyAppTracker.process(
            [reading(1, app: "App", nj: 1_004_000_000_000, cpu: 0)],
            at: t0.addingTimeInterval(610), systemWatts: nil, state: state
        )
        XCTAssertEqual(next.usage.first?.watts ?? 0, 0.5, accuracy: 1e-9)
    }

    func testVanishedPIDLeavesStaleState() {
        // When a PID disappears, its state must not linger forever: the seed
        // step rebuilds from the current tick, so nothing accumulates.
        let state = EnergyAppTracker.makeState()
        _ = EnergyAppTracker.process(
            [
                reading(1, app: "App", nj: 0, cpu: 0),
                reading(2, app: "Gone", nj: 0, cpu: 0),
            ],
            at: t0, systemWatts: nil, state: state
        )
        _ = EnergyAppTracker.process(
            [reading(1, app: "App", nj: 1_000, cpu: 0)],
            at: t0.addingTimeInterval(10), systemWatts: nil, state: state
        )
        // Only the live PID remains.
        XCTAssertEqual(state.pids.count, 1)
        XCTAssertNil(state.pids[2])
    }

    func testReversedSortTieBreaksByName() {
        let state = EnergyAppTracker.makeState()
        _ = EnergyAppTracker.process(
            [
                reading(1, app: "Zebra", nj: 0, cpu: 0),
                reading(2, app: "Alpha", nj: 0, cpu: 0),
            ],
            at: t0, systemWatts: nil, state: state
        )
        // Identical draws → alphabetical tie-break.
        let result = EnergyAppTracker.process(
            [
                reading(1, app: "Zebra", nj: 10_000_000_000, cpu: 0),
                reading(2, app: "Alpha", nj: 10_000_000_000, cpu: 0),
            ],
            at: t0.addingTimeInterval(10), systemWatts: nil, state: state
        )
        XCTAssertEqual(result.usage.map(\.name), ["Alpha", "Zebra"])
    }
}
