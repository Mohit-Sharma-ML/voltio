import Foundation

/// Pure, deterministic logic for remembering devices so accessories stay listed
/// (with their last-known battery) after they disconnect. Kept free of storage so
/// it can be unit-tested in isolation; the app layer owns persistence.
public enum DeviceHistory {
    /// Fold the currently-connected devices into the remembered map, refreshing
    /// each one's `lastSeen`. An empty `live` set leaves history untouched so a
    /// momentary gap in readings never wipes what we know.
    public static func record(
        live: [PeripheralDevice],
        into remembered: [String: PeripheralDevice],
        now: Date = Date()
    ) -> [String: PeripheralDevice] {
        guard !live.isEmpty else { return remembered }
        var result = remembered
        for device in live {
            result[device.id] = device.setting(isConnected: true, lastSeen: now)
        }
        return result
    }

    /// Connected devices (live) followed by remembered offline ones, ranked by
    /// `order`. A device present in both is shown once, as connected.
    public static func merge(
        live: [PeripheralDevice],
        remembered: [String: PeripheralDevice]
    ) -> [PeripheralDevice] {
        let liveIDs = Set(live.map(\.id))
        var result = live.map { $0.setting(isConnected: true) }
        for (id, device) in remembered where !liveIDs.contains(id) {
            result.append(device.setting(isConnected: false))
        }
        return result.sorted(by: order)
    }

    /// Whether two remembered maps hold the same devices and readings, ignoring
    /// `lastSeen` (which advances every poll). Used to decide whether a change is
    /// *material* enough to warrant re-persisting, instead of writing to disk on
    /// every tick just because a timestamp moved.
    public static func sameContent(
        _ a: [String: PeripheralDevice],
        _ b: [String: PeripheralDevice]
    ) -> Bool {
        guard a.count == b.count else { return false }
        for (id, da) in a {
            guard let db = b[id] else { return false }
            if da.name != db.name || da.batteries != db.batteries { return false }
        }
        return true
    }

    /// Remembered devices not seen within `expiry` are dropped.
    public static func pruneExpired(
        _ remembered: [String: PeripheralDevice],
        expiry: TimeInterval,
        now: Date = Date()
    ) -> [String: PeripheralDevice] {
        let cutoff = now.addingTimeInterval(-expiry)
        return remembered.filter { $0.value.lastSeen >= cutoff }
    }

    /// Connected before offline; then lowest battery first; then name (A→Z).
    public static func order(_ a: PeripheralDevice, _ b: PeripheralDevice) -> Bool {
        if a.isConnected != b.isConnected { return a.isConnected && !b.isConnected }
        let pa = a.minPercent ?? Int.max
        let pb = b.minPercent ?? Int.max
        if pa != pb { return pa < pb }
        return a.name < b.name
    }
}
