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

/// Reads the native macOS charge-limit configuration. All sources are
/// read-only public surfaces (`pmset -g battlimit`, `defaults read`);
/// no private API is involved — see `Docs/gap2-charge-limit.md` for why
/// the write path is off the table.
public struct ChargeLimitReader: Sendable {
    /// The pmset binary location. Injected for testability.
    private let pmsetPath: String
    /// The defaults domain holding the battery UI's prior hold target.
    private let batteryUIDomain: String
    private let batteryUIKey = "com.apple.batteryui.charging.mac.prior.limit"

    public init(
        pmsetPath: String = "/usr/bin/pmset",
        batteryUIDomain: String = "com.apple.batteryui.charging.mac"
    ) {
        self.pmsetPath = pmsetPath
        self.batteryUIDomain = batteryUIDomain
    }

    /// Reads the current charge-limit state. Cheap enough to run on every
    /// battery poll tick (two subprocess spawns, no IOKit work).
    public func read() -> ChargeLimitState {
        ChargeLimitState(percent: readPmsetLimit() ?? readPriorLimit())
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

    /// Falls back to the battery UI's "prior limit" — the hold target the
    /// charging UI last enforced (Optimized Charging's ~80% target or the
    /// user's chosen Charge Limit). Only consulted when pmset reports no
    /// limit, and only trusted when it sits in the native 80–100 range.
    private func readPriorLimit() -> Int? {
        guard let value = UserDefaults(suiteName: batteryUIDomain)?
            .object(forKey: batteryUIKey) as? Int,
            (80...100).contains(value)
        else { return nil }
        return value
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
