import Foundation
import PowerCore

/// `UserDefaults`-backed store that remembers each device's last battery reading
/// so accessories stay visible (greyed, "last seen …") after they disconnect —
/// macOS keeps no readable cache for this, so we maintain our own.
///
/// All decision logic lives in `PowerCore.DeviceHistory`; this type only owns
/// persistence and the expiry window.
@MainActor
final class DeviceHistoryStore {
    private let defaults: UserDefaults
    private let key: String
    private let expiry: TimeInterval
    /// How often `lastSeen`-only changes are flushed to disk. Material changes
    /// (device added/removed, battery moved) always persist immediately.
    private let lastSeenFlushInterval: TimeInterval
    /// Injected so tests can drive expiry/flush behavior deterministically.
    private let now: () -> Date
    private var lastPersist = Date.distantPast

    private(set) var remembered: [String: PeripheralDevice]

    init(
        defaults: UserDefaults = .standard,
        key: String = "deviceHistory.v1",
        expiry: TimeInterval = 3 * 24 * 3600,
        lastSeenFlushInterval: TimeInterval = 300,
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.key = key
        self.expiry = expiry
        self.lastSeenFlushInterval = lastSeenFlushInterval
        self.now = now
        self.remembered = Self.load(defaults, key)

        // Drop anything that should never have been persisted: BLE Continuity
        // adverts (rotating-UUID ids) and entries past the expiry window. This
        // also scrubs history written by earlier builds that remembered adverts.
        let cleaned = DeviceHistory.pruneExpired(remembered, expiry: expiry, now: now())
            .filter { $0.value.hasStableIdentity }
        if cleaned.count != remembered.count {
            remembered = cleaned
            persist()
        }
    }

    /// Refresh last-known readings from the devices currently reporting. Persists
    /// immediately on a material change; a `lastSeen`-only refresh is flushed at
    /// most every `lastSeenFlushInterval` to avoid a disk write on every poll.
    func record(_ live: [PeripheralDevice]) {
        let updated = DeviceHistory.record(live: live, into: remembered, now: now())
        guard updated != remembered else { return }
        let materialChange = !DeviceHistory.sameContent(updated, remembered)
        remembered = updated
        if materialChange || now().timeIntervalSince(lastPersist) >= lastSeenFlushInterval {
            persist()
        }
    }

    /// Connected devices first, then remembered offline ones, ranked by battery.
    func merged(withLive live: [PeripheralDevice]) -> [PeripheralDevice] {
        DeviceHistory.merge(live: live, remembered: remembered)
    }

    /// Permanently forget a remembered device.
    func forget(_ id: String) {
        guard remembered[id] != nil else { return }
        remembered[id] = nil
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(remembered) else { return }
        defaults.set(data, forKey: key)
        lastPersist = now()
    }

    private static func load(_ defaults: UserDefaults, _ key: String) -> [String: PeripheralDevice] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: PeripheralDevice].self, from: data)
        else { return [:] }
        return decoded
    }
}
