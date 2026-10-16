import Foundation

/// Smooths instantaneous battery power readings with an exponentially weighted
/// moving average so the power flow diagram doesn't jitter between polls.
///
/// Pure value type — mutation returns a new instance — so it stays trivially
/// testable and safe to hold inside an `@Observable` model.
public struct PowerEstimator: Sendable, Equatable {
    /// Samples older than this are dropped rather than folded into the average,
    /// so waking from sleep doesn't smear stale readings into the estimate.
    public static let sampleMaxAge: TimeInterval = 15 * 60

    /// Recency weight: higher alpha reacts faster, lower is smoother.
    /// 0.35 settles over ~4–6 samples — responsive without twitching.
    public static let alpha: Double = 0.35

    private var smoothed: Double?
    private var lastUpdate: Date?

    public init() {}

    /// Current smoothed estimate in watts, or `nil` until a sample arrives.
    public var estimateWatts: Double? { smoothed }

    /// Feeds a new power sample and returns the updated estimator.
    /// - Parameters:
    ///   - watts: instantaneous power (negative while discharging).
    ///   - now: sample timestamp, injected for testability.
    public func updated(with watts: Double, at now: Date) -> PowerEstimator {
        var copy = self

        // Drop stale state instead of decaying toward it: after sleep, an old
        // estimate is simply wrong.
        if let last = lastUpdate, now.timeIntervalSince(last) > Self.sampleMaxAge {
            copy.smoothed = nil
            copy.lastUpdate = nil
        }

        if let current = copy.smoothed {
            copy.smoothed = current + Self.alpha * (watts - current)
        } else {
            copy.smoothed = watts
        }
        copy.lastUpdate = now
        return copy
    }

    public func reset() -> PowerEstimator {
        PowerEstimator()
    }
}
