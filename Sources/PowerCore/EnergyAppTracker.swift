import Foundation

/// Per-app energy attribution math.
///
/// Pure logic only — no AppKit, no `proc_*` calls. The sampler
/// (`EnergyAppsSampler` in the app target) feeds raw per-process rusage
/// readings in; this type turns them into per-app power figures.
///
/// Two measurement paths exist because macOS does not always expose hardware
/// energy counters per process:
///
/// 1. **Energy counters** (`rusage_info_v6.ri_energy_nj`, cumulative
///    nanojoules). When the kernel populates them (verified on Apple Silicon),
///    power is simply the counter delta divided by the elapsed time between
///    samples. This directly measures what the process consumed.
/// 2. **CPU-time fallback**: when energy counters are absent (they read as 0 on
///    some configurations), attribute a share of the *measured system power*
///    (the battery draw the app already tracks) proportional to each process's
///    CPU-time delta. This keeps attribution honest — app shares always sum to
///    the real draw — but it is an estimate: a process can burn energy on the
///    GPU or disk without CPU time.
///
/// All bookkeeping is keyed by process ID and rolled up to an *app identity*
/// (bundle path directory) by the caller; this type never talks to the OS.
public enum EnergyAppTracker {

    /// One per-process rusage reading fed in by the sampler.
    ///
    /// `Sendable` so samplers can collect readings off the main actor and
    /// hand them across an isolation boundary to the tracker.
    public struct Reading: Equatable, Sendable {

        /// Process ID from `proc_pid`.
        public let pid: pid_t

        /// App identity — usually the bundle's containing directory
        /// (e.g. `/Applications/Voltio.app`). Processes outside a bundle
        /// (daemons, CLI tools) use the executable's directory instead.
        public let appID: String

        /// Human-facing name (executable name or localized bundle name).
        public let name: String

        /// Cumulative per-process energy in nanojoules
        /// (`rusage_info_v6.ri_energy_nj`). Zero when the kernel does not
        /// populate energy counters.
        public let energyNJ: UInt64

        /// Cumulative CPU time. Because the raw rusage units are unreliable
        /// across configurations, this is *normalized CPU-seconds*: the caller
        /// must convert `ri_user_time`/`ri_system_time` via
        /// `mach_timebase_info` before constructing a Reading.
        public let cpuSeconds: Double

        public init(
            pid: pid_t, appID: String, name: String,
            energyNJ: UInt64, cpuSeconds: Double
        ) {
            self.pid = pid
            self.appID = appID
            self.name = name
            self.energyNJ = energyNJ
            self.cpuSeconds = cpuSeconds
        }
    }

    /// One app's attributed draw over the last tick.
    public struct AppUsage: Identifiable, Equatable {

        public var id: String { appID }

        /// App identity (see `Reading.appID`).
        public let appID: String

        /// Display name (most recently observed for this app).
        public let name: String

        /// Attributed average power in watts over the tick.
        public let watts: Double

        /// How the figure was derived.
        public let method: Method

        public enum Method: Equatable {
            /// Hardware energy counters: `ΔenergyNJ / Δt`. Direct measurement.
            case energyCounters
            /// CPU-time share × measured system watts. An estimate.
            case cpuShare
        }

        /// The number of processes of this app that were seen this tick.
        public let processCount: Int

        public init(
            appID: String, name: String, watts: Double,
            method: Method, processCount: Int
        ) {
            self.appID = appID
            self.name = name
            self.watts = watts
            self.method = method
            self.processCount = processCount
        }
    }

    /// Result of folding one tick of readings into the running totals.
    public struct TickResult: Equatable {

        /// Apps sorted by attributed power, highest draw first. Apps with a
        /// negligible (~zero) draw are excluded.
        public let usage: [AppUsage]

        /// True when every app figure came from energy counters (direct
        /// measurement). False when the CPU-share fallback was used (at least
        /// in part).
        public let measuredEnergy: Bool
    }

    /// Mutable per-PID bookkeeping between ticks.
    struct PIDState {
        var appID: String
        var name: String
        var lastEnergyNJ: UInt64
        var lastCPUSeconds: Double
    }

    // MARK: - Configuration

    /// Apps whose instantaneous draw is below this are dropped from the
    /// visible list. Keeps idle-system output from being noise.
    private static let minimumWatts = 0.05

    // MARK: - State machine

    /// The per-PID state carried between ticks.
    public final class State {
        var pids: [pid_t: PIDState] = [:]
        /// Wall-clock time of the previous tick.
        var lastSampleDate: Date?
    }

    /// Creates fresh, empty tracker state.
    public static func makeState() -> State { State() }

    /// Folds one tick of per-process readings into per-app power figures.
    ///
    /// - Parameters:
    ///   - readings: per-process readings sampled *now*.
    ///   - date: wall-clock time of this sample (injectable for tests).
    ///   - systemWatts: the measured whole-system draw (EMA-smoothed battery
    ///     power). Only used by the CPU-share fallback.
    ///   - state: mutable bookkeeping returned to the next call.
    /// - Returns: per-app usage, highest draw first. Empty until the second
    ///   tick (deltas need a baseline).
    public static func process(
        _ readings: [Reading],
        at date: Date,
        systemWatts: Double?,
        state: State
    ) -> TickResult {
        // First tick: record the baseline, no deltas exist yet.
        guard let lastDate = state.lastSampleDate else {
            seedBaseline(readings, into: state, at: date)
            return TickResult(usage: [], measuredEnergy: true)
        }

        let elapsed = date.timeIntervalSince(lastDate)
        defer { seedBaseline(readings, into: state, at: date) }

        // Elapsed time must be sane; a clock jump (sleep/wake) would produce
        // a wild rate. Skip the tick and reseed instead.
        guard elapsed > 0.5, elapsed < 60 else {
            return TickResult(usage: [], measuredEnergy: true)
        }

        // Roll per-PID deltas up by app identity.
        var energyNJByApp: [String: UInt64] = [:]
        var cpuSecondsByApp: [String: Double] = [:]
        var namesByApp: [String: String] = [:]
        var processCountByApp: [String: Int] = [:]
        var sawAnyEnergyCounter = false

        for reading in readings {
            guard let previous = state.pids[reading.pid] else { continue }
            // New PID this tick has no baseline — seeded for next time.
            // (Also covers PID reuse: the counters of the new process are
            // unrelated to the old entry's.)
            if previous.appID != reading.appID || previous.name != reading.name {
                continue
            }

            let energyDelta = reading.energyNJ >= previous.lastEnergyNJ
                ? reading.energyNJ - previous.lastEnergyNJ
                : 0  // counter reset (process restart within same PID is impossible; be safe anyway)
            let cpuDelta = max(0, reading.cpuSeconds - previous.lastCPUSeconds)

            energyNJByApp[reading.appID, default: 0] += energyDelta
            cpuSecondsByApp[reading.appID, default: 0] += cpuDelta
            namesByApp[reading.appID] = reading.name
            processCountByApp[reading.appID, default: 0] += 1
            if reading.energyNJ > 0 { sawAnyEnergyCounter = true }
        }

        var usage: [AppUsage] = []
        var allMeasured = sawAnyEnergyCounter

        if sawAnyEnergyCounter {
            // Direct path: nJ → W is nJ / (s × 1e9).
            for (appID, energyNJ) in energyNJByApp {
                let watts = Double(energyNJ) / (elapsed * 1e9)
                let count = processCountByApp[appID] ?? 0
                usage.append(AppUsage(
                    appID: appID,
                    name: namesByApp[appID] ?? appID,
                    watts: watts,
                    method: .energyCounters,
                    processCount: count
                ))
            }
        } else {
            // Fallback: distribute measured system power by CPU share.
            allMeasured = false
            let totalCPU = cpuSecondsByApp.values.reduce(0, +)
            if totalCPU > 0, let systemWatts, systemWatts > 0 {
                for (appID, cpu) in cpuSecondsByApp {
                    let share = cpu / totalCPU
                    let watts = share * systemWatts
                    let count = processCountByApp[appID] ?? 0
                    usage.append(AppUsage(
                        appID: appID,
                        name: namesByApp[appID] ?? appID,
                        watts: watts,
                        method: .cpuShare,
                        processCount: count
                    ))
                }
            }
        }

        // Drop negligible draws and sort highest first.
        usage = usage.filter { $0.watts >= minimumWatts }
            .sorted { lhs, rhs in
                lhs.watts != rhs.watts
                    ? lhs.watts > rhs.watts
                    : lhs.name < rhs.name
            }
        return TickResult(usage: usage, measuredEnergy: allMeasured)
    }

    /// Records the current readings as the baseline for the next tick.
    private static func seedBaseline(
        _ readings: [Reading], into state: State, at date: Date
    ) {
        var next: [pid_t: PIDState] = [:]
        next.reserveCapacity(readings.count)
        for r in readings {
            next[r.pid] = PIDState(
                appID: r.appID,
                name: r.name,
                lastEnergyNJ: r.energyNJ,
                lastCPUSeconds: r.cpuSeconds
            )
        }
        state.pids = next
        state.lastSampleDate = date
    }
}
