import Foundation
import IOBluetooth

/// Owns the Continuity ownership gate (Phase 1.3 extraction from
/// BluetoothBatteryScanner): decides whether a `ble:` device decoded from an
/// Apple Continuity advert may be shown.
///
/// Two confirmation paths, checked in order:
/// 1. **Paired-name match** — the advert's LocalName equals a device in the
///    system's IOBluetooth paired list (the same GAP name field on both
///    sides). Covers audio-stack connections (AirPods playing audio), which
///    are invisible to CoreBluetooth's `retrieveConnectedPeripherals` —
///    they connect via the ACL/audio path, not app-level GATT.
/// 2. **Connect-to-confirm** — the system has connected to a device of this
///    name at least once (observed via CB's connected-peripheral set).
///
/// True strangers' adverts never match either path. Confirmed names persist
/// for the process lifetime; cross-launch identity rides on
/// `DeviceHistoryStore`. Pure name logic — the scanner supplies the visible
/// device names, keeping this type free of CoreBluetooth state and unit
/// testable without a radio.
@MainActor
final class ContinuityOwnershipTracker {

    /// Names from the Continuity path confirmed as owned.
    private(set) var confirmedOwnedNames: Set<String> = []

    /// The system's paired-device names (IOBluetooth, refreshed lazily).
    private var pairedNames: Set<String>?
    private var pairedNamesFetchedAt: Date?

    /// The paired-name source; production queries IOBluetooth. `var` (not
    /// injected at init) so the tracker can be constructed in tests without
    /// touching the framework.
    nonisolated(unsafe) static var pairedNamesProvider: () -> Set<String>? = fetchPairedNames

    /// Case/space-insensitive name normalization for matching an advert's
    /// local name against the system's paired/connected names.
    nonisolated static func normalizedName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    /// True when a Continuity device with this (raw, un-normalized) name may
    /// be shown: confirmed owned, or matches the paired list.
    func isOwned(name rawName: String) -> Bool {
        let name = rawName.lowercased()
        if confirmedOwnedNames.contains(name) { return true }
        return pairedNames?.contains(name) ?? false
    }

    /// Confirm visible devices whose name is in `systemConnectedNames` (the
    /// system just connected to them). Returns the set of newly confirmed
    /// names so the caller can re-emit when non-empty. Idempotent per
    /// connected-set: re-running with the same set is a no-op.
    @discardableResult
    func confirmVisible(
        _ visibleNames: Set<String>,
        connectedTo systemConnectedNames: Set<String>
    ) -> Set<String> {
        guard systemConnectedNames != lastSystemConnectedNames else { return [] }
        lastSystemConnectedNames = systemConnectedNames
        return confirmIntersection(systemConnectedNames, among: visibleNames)
    }

    /// Refresh the paired-names cache (at most once per 10 minutes — the
    /// paired list rarely changes). When the freshly-fetched list confirms
    /// any currently-visible device, the new names are returned so the
    /// caller can re-emit.
    @discardableResult
    func refreshPairedNamesIfStale(
        now: Date = Date(),
        visibleNames: Set<String>
    ) -> Set<String> {
        if let fetched = pairedNamesFetchedAt, now.timeIntervalSince(fetched) < 600 {
            return []
        }
        pairedNames = Self.pairedNamesProvider()
        pairedNamesFetchedAt = now
        guard let pairedNames else { return [] }
        return confirmIntersection(pairedNames, among: visibleNames)
    }

    /// Confirms every visible name present in `source`; returns the newly
    /// confirmed ones.
    private func confirmIntersection(
        _ source: Set<String>,
        among visibleNames: Set<String>
    ) -> Set<String> {
        let newlyConfirmed = visibleNames.intersection(source)
            .subtracting(confirmedOwnedNames)
        confirmedOwnedNames.formUnion(newlyConfirmed)
        return newlyConfirmed
    }

    /// Query the system paired list. Nonisolated + static: IOBluetooth's
    /// pairedDevices() is thread-safe for local reads and keeps IOBluetooth
    /// types out of MainActor-isolated scanner state.
    nonisolated static func fetchPairedNames() -> Set<String>? {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }
        return Set(paired.compactMap { normalizedName($0.name as String?) })
    }

    private var lastSystemConnectedNames: Set<String> = []
}
