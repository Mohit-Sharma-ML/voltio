import Foundation

/// A snapshot of macOS's native battery charge-limit state.
///
/// Since macOS 26.4, System Settings → Battery offers a user-configurable
/// Charge Limit (80–100%) enforced by `powerd` behind a private entitlement.
/// The configured value isn't in any public API, but `pmset -g battlimit`
/// (a read-only getter) prints it — see `ChargeLimitReader` — and the
/// battery UI layer keeps its prior hold target in the
/// `com.apple.batteryui.charging.mac` defaults domain.
public struct ChargeLimitState: Sendable, Equatable {
    /// The user-configured native charge limit, in percent (80–100), when one
    /// is set. `nil` when the system reports no limit.
    public let percent: Int?

    /// `true` when a native limit is configured.
    public var isEnabled: Bool { percent != nil }

    public init(percent: Int?) {
        self.percent = percent.map { max(0, min(100, $0)) }
    }
}

/// Reads the native macOS charge-limit configuration. The only source is
/// `pmset -g battlimit` (a read-only getter, safe to spawn from the sandbox —
/// the child inherits the App Sandbox but powerd's XPC service is reachable).
/// The `com.apple.batteryui.charging.mac` defaults domain is NOT readable from
/// a sandboxed app (cfprefsd cages foreign domains to an empty view), so it is
/// deliberately not consulted. No private API is involved — see
/// `Docs/gap2-charge-limit.md` for why the write path is off the table.
public struct ChargeLimitReader: Sendable {
    /// The pmset binary location. Injected for testability.
    private let pmsetPath: String

    public init(pmsetPath: String = "/usr/bin/pmset") {
        self.pmsetPath = pmsetPath
    }

    /// Reads the current charge-limit state. Runs I/O — call from a
    /// background queue (see `BatteryModel.refreshChargeLimit`).
    public func read() -> ChargeLimitState {
        ChargeLimitState(percent: readPmsetLimit())
    }

    /// Parses `pmset -g battlimit`. With no limit set it prints
    /// "No battery level limits set"; when set, powerd prints a
    /// "Battery level limits:" block whose rows carry `level=NN`.
    private func readPmsetLimit() -> Int? {
        guard let output = run(pmsetPath, ["-g", "battlimit"]) else { return nil }
        return Self.parsePmsetOutput(output)
    }

    /// Parses the `pmset -g battlimit` text. Pure and unit-testable.
    ///
    /// Accepts any row of the form `level=NN` (the only numeric encoding
    /// powerd currently emits for SOC limits) and ignores the "no limits"
    /// sentinel. If multiple rows ever appear, the first wins.
    public static func parsePmsetOutput(_ text: String) -> Int? {
        let lower = text.lowercased()
        guard !lower.contains("no battery level limits set") else { return nil }
        for line in text.split(separator: "\n") {
            if let range = line.range(of: "level=") {
                let digits = line[range.upperBound...].prefix { $0.isNumber }
                if let percent = Int(digits) {
                    return percent
                }
            }
        }
        return nil
    }

    private func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        // pmset output is tiny (well under the 64 KB pipe buffer), so reading
        // to EOF before waiting can't deadlock. `waitUntilExit` must complete
        // before `terminationStatus` is touched — accessing it earlier throws
        // an Objective-C exception (observed 2026-10-16).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
