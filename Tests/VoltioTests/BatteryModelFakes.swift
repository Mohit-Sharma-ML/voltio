import Foundation
import PowerCore
@testable import Voltio

/// Fakes for `BatteryModel`'s collaborators (Phase 0 safety net — see
/// Docs/hardening-plan.md). Deterministic, no IOKit/WidgetKit/defaults touch.

/// Scripted battery readings: each `read()` pops the next state, holding the
/// last one forever after the script is exhausted.
final class FakeBatteryProvider: BatteryReadingProviding, @unchecked Sendable {
    private let states: [BatterySnapshot]
    private var index = 0
    private let lock = NSLock()

    /// Count of `read()` calls (the model polls; this tracks tick count).
    private(set) var readCount = 0

    init(states: [BatterySnapshot]) {
        assert(!states.isEmpty, "FakeBatteryProvider needs at least one state")
        self.states = states
    }

    func read() throws -> BatterySnapshot {
        lock.lock()
        defer { lock.unlock() }
        readCount += 1
        return states[min(index, states.count - 1)]
    }

    /// Advance to the next scripted state (test drives time forward).
    func advance() {
        lock.lock()
        defer { lock.unlock() }
        index = min(index + 1, states.count - 1)
    }
}

/// Records every publish call so tests can assert exactly what the model
/// handed to the widget pipeline (and when reloads were forced).
final class FakeWidgetPublisher: WidgetPublishing {
    struct Call: Equatable {
        let percentage: Int
        let isCharging: Bool
        let isPluggedIn: Bool
        let isChargeHold: Bool
        let forceReload: Bool
        let date: Date
    }

    private let lock = NSLock()
    private(set) var calls: [Call] = []

    var publishCount: Int { lock.withLock { calls.count } }

    func publish(
        _ snapshot: BatterySnapshot,
        todayEnergy: EnergyAggregator.DayTotal?,
        smoothedPowerWatts: Double?,
        at date: Date,
        forceReload: Bool
    ) {
        lock.lock()
        defer { lock.unlock() }
        calls.append(Call(
            percentage: snapshot.percentage,
            isCharging: snapshot.isCharging,
            isPluggedIn: snapshot.isPluggedIn,
            isChargeHold: snapshot.isPausedByMacOS,
            forceReload: forceReload,
            date: date
        ))
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        calls = []
    }
}

/// Scripted charge-limit state (tests flip it between ticks).
final class FakeChargeLimitReader: ChargeLimitReading, @unchecked Sendable {
    private let lock = NSLock()
    private var state: ChargeLimitState

    init(initial: ChargeLimitState = ChargeLimitState(percent: nil)) {
        self.state = initial
    }

    func read() -> ChargeLimitState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func set(_ newState: ChargeLimitState) {
        lock.lock()
        defer { lock.unlock() }
        state = newState
    }
}

// MARK: - Snapshot builders

enum ModelTestSnapshots {
    /// A snapshot with sensible defaults; override per test.
    static func make(
        percentage: Int = 80,
        isCharging: Bool = false,
        isPluggedIn: Bool = false,
        isFullyCharged: Bool = false,
        isLowPowerMode: Bool = false,
        notChargingReason: BatterySnapshot.NotChargingReason? = nil
    ) -> BatterySnapshot {
        BatterySnapshot(
            percentage: percentage,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isFullyCharged: isFullyCharged,
            isLowPowerMode: isLowPowerMode,
            minutesRemaining: nil,
            cycleCount: 100,
            designCycleCount: 1000,
            temperatureCelsius: 28,
            voltage: 11.6,
            amperage: 0,
            currentCapacitymAh: 4000,
            maxCapacitymAh: 8000,
            designCapacitymAh: 8800,
            adapterWatts: isPluggedIn ? 96 : nil,
            adapterName: nil,
            systemPowerWatts: nil,
            batteryPowerWatts: nil,
            notChargingReason: notChargingReason
        )
    }
}
