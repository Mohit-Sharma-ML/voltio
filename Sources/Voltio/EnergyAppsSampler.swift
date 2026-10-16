import Foundation
import PowerCore

/// Samples per-process rusage on the poll cadence and folds it into per-app
/// energy attribution for the panel's "Apps Using Significant Energy" section.
///
/// This type is OS plumbing only: it walks the process table
/// (`proc_listallpids`), reads `rusage_info_v6` via `proc_pid_rusage` (public
/// API since macOS 10.9, no entitlements needed non-sandboxed), and maps each
/// process to an app identity. All the math — delta clamping, app rollup,
/// watts conversion, the CPU-share fallback — lives in the pure
/// `PowerCore.EnergyAppTracker`, which is unit-tested.
///
/// Empirical notes from probing on Apple Silicon (macOS 26):
/// - `ri_energy_nj` is populated and cumulative → direct per-process
///   measurement. The v4 billed/serviced fields are *not* populated here.
/// - `ri_user_time`/`ri_system_time` are raw mach absolute-time ticks, not
///   nanoseconds; they must be converted via `mach_timebase_info`.
///
/// The process-table walk runs off the main actor (a detached utility task);
/// folding the readings into the tracker state is cheap and happens here on
/// the main actor so published state stays consistent with the rest of the
/// model layer.
@MainActor
final class EnergyAppsSampler {

    /// Tracker state carried across ticks (per-PID baselines). Injected so the
    /// clock-jump/skip semantics of `EnergyAppTracker` are preserved verbatim.
    private var trackerState = EnergyAppTracker.makeState()

    /// Latest per-app usage, sorted highest draw first. Empty until two ticks
    /// have run (the first tick only seeds baselines).
    private(set) var usage: [EnergyAppTracker.AppUsage] = []

    /// True when the kernel populates hardware energy counters for this
    /// machine (direct measurement); false when figures fall back to the
    /// CPU-share estimate.
    private(set) var usesEnergyCounters = true

    /// Samples once: collects rusage for all processes off-main, then folds
    /// the readings into the tracker. Safe to call on every ~5 s battery tick;
    /// the walk is a few hundred lightweight syscalls (~1 ms in practice).
    func tick(systemWatts: Double?, at date: Date = Date()) async {
        let readings = await Task.detached(priority: .utility) {
            Self.collectReadings()
        }.value
        let result = EnergyAppTracker.process(
            readings, at: date, systemWatts: systemWatts, state: trackerState
        )
        usage = result.usage
        usesEnergyCounters = result.measuredEnergy
    }

    // MARK: - OS collection (runs off the main actor)

    /// Walks the process table and produces one `Reading` per process that
    /// exposes an energy counter or CPU time. Kernel processes and zombies
    /// (no resolvable path) are skipped.
    nonisolated static func collectReadings() -> [EnergyAppTracker.Reading] {
        let count = Int(proc_listallpids(nil, 0))
        guard count > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: count)
        let actual = proc_listallpids(&pids, Int32(count * MemoryLayout<pid_t>.stride))
        guard actual > 0 else { return [] }

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let tickScale = Double(timebase.numer) / Double(timebase.denom)

        var readings: [EnergyAppTracker.Reading] = []
        readings.reserveCapacity(Int(actual))
        for pid in pids.prefix(Int(actual)) where pid > 0 {
            guard let (appID, name) = identity(for: pid) else { continue }

            var info = rusage_info_v6()
            let status = withUnsafeMutableBytes(of: &info) { raw -> Int32 in
                let base = raw.baseAddress!.assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
                return proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, base)
            }
            guard status == 0 else { continue }

            // Raw ticks → CPU-seconds (see class doc: NOT nanoseconds).
            let cpuSeconds =
                (Double(info.ri_user_time) + Double(info.ri_system_time))
                * tickScale / 1e9

            readings.append(EnergyAppTracker.Reading(
                pid: pid,
                appID: appID,
                name: name,
                energyNJ: info.ri_energy_nj,
                cpuSeconds: cpuSeconds
            ))
        }
        return readings
    }

    /// Maps a process to its app identity. Processes inside a bundle resolve
    /// to the `.app` directory (e.g. `/Applications/Safari.app`, named
    /// "Safari"); everything else uses the executable's directory and file
    /// name (daemons, CLI tools).
    nonisolated static func identity(for pid: pid_t) -> (appID: String, name: String)? {
        // 4 * MAXPATHLEN — same value as the C macro, which Swift does not
        // expose from proc_info.h.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        // bufferSize is imported as UInt32; the return value is the path
        // length in bytes (not counting the null terminator).
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        let path = String(decoding: bytes, as: UTF8.self)

        let components = path.split(separator: "/")
        guard let last = components.last else { return nil }

        // Longest ".app" component that is not the executable itself.
        if let index = components.lastIndex(where: { $0.hasSuffix(".app") }),
           index < components.count - 1 {
            let bundleName = String(components[index].dropLast(4))
            let appID = "/" + components[...index].joined(separator: "/")
            return (appID, bundleName.isEmpty ? String(last) : bundleName)
        }

        let appID = components.count > 1 ? "/" + components.dropLast().joined(separator: "/") : path
        return (appID, String(last))
    }
}
