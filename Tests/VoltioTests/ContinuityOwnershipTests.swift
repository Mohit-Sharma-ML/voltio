import Foundation
import XCTest
@testable import Voltio

/// Ownership gating for Continuity (AirPods) BLE devices, exercised through
/// the extracted `ContinuityOwnershipTracker` (Phase 1.3).
///
/// The Continuity path fires for ANY Apple device in radio range (RSSI ≥ -65
/// is proximity, not ownership) — a colleague's or stranger's AirPods would
/// otherwise appear in the Devices list. A device is shown only once its name
/// matches the system's paired list (paired-name matching) or the system has
/// connected to it at least once (connect-to-confirm).
@MainActor
final class ContinuityOwnershipTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Never touch IOBluetooth from tests.
        ContinuityOwnershipTracker.pairedNamesProvider = { nil }
        ContinuityOwnershipTracker.pairedAddressSuffixProvider = { [] }
    }

    override func tearDown() {
        ContinuityOwnershipTracker.pairedNamesProvider = ContinuityOwnershipTracker.fetchPairedNames
        ContinuityOwnershipTracker.pairedAddressSuffixProvider =
            ContinuityOwnershipTracker.pairedDeviceAddressSuffixes
        super.tearDown()
    }

    // MARK: - Name normalization

    func testNormalizedNameTrimsAndLowercases() {
        XCTAssertEqual(ContinuityOwnershipTracker.normalizedName("  Mohit's AirPods "), "mohit's airpods")
        XCTAssertEqual(ContinuityOwnershipTracker.normalizedName("MX MASTER 3 B"), "mx master 3 b")
    }

    func testNormalizedNameNilForBlank() {
        XCTAssertNil(ContinuityOwnershipTracker.normalizedName(nil))
        XCTAssertNil(ContinuityOwnershipTracker.normalizedName("   "))
        XCTAssertNil(ContinuityOwnershipTracker.normalizedName(""))
    }

    // MARK: - Paired-name path

    func testPairedNameMatchConfirmsOwnership() {
        let tracker = ContinuityOwnershipTracker()
        ContinuityOwnershipTracker.pairedNamesProvider = { ["airpods 4 (anc)"] }

        // Unconfirmed before the refresh sees the paired list.
        XCTAssertFalse(tracker.isOwned(name: "AirPods 4 (ANC)"))

        let changed = tracker.refreshPairedNamesIfStale(visibleNames: ["airpods 4 (anc)"])
        XCTAssertEqual(changed, ["airpods 4 (anc)"])
        XCTAssertTrue(tracker.isOwned(name: "AirPods 4 (ANC)"))
    }

    func testStrangerNameNeverConfirmed() {
        let tracker = ContinuityOwnershipTracker()
        ContinuityOwnershipTracker.pairedNamesProvider = { ["airpods 4 (anc)"] }

        tracker.refreshPairedNamesIfStale(visibleNames: ["colleague's airpods"])
        XCTAssertFalse(tracker.isOwned(name: "colleague's airpods"))
    }

    func testPairedListGrantsOwnershipEvenBeforeVisibility() {
        // Current shipped behavior: membership in the system's paired list is
        // itself the ownership test (isOwned checks pairedNames directly), so
        // a paired device is trusted the moment the cache is populated —
        // visibility is not required for the paired-name path.
        let tracker = ContinuityOwnershipTracker()
        ContinuityOwnershipTracker.pairedNamesProvider = { ["airpods 4 (anc)"] }

        tracker.refreshPairedNamesIfStale(visibleNames: [])
        XCTAssertTrue(tracker.confirmedOwnedNames.isEmpty) // nothing *confirmed*...
        XCTAssertTrue(tracker.isOwned(name: "airpods 4 (anc)")) // ...but paired ⇒ owned
    }

    func testPairedCacheThrottledToTenMinutes() {
        let tracker = ContinuityOwnershipTracker()
        var calls = 0
        ContinuityOwnershipTracker.pairedNamesProvider = {
            calls += 1
            return ["x"]
        }

        let now = Date()
        tracker.refreshPairedNamesIfStale(now: now, visibleNames: ["x"])
        tracker.refreshPairedNamesIfStale(
            now: now.addingTimeInterval(9 * 60), visibleNames: ["x"])
        XCTAssertEqual(calls, 1) // within the 10-minute window: cached

        let changed = tracker.refreshPairedNamesIfStale(
            now: now.addingTimeInterval(10 * 60 + 1), visibleNames: ["x"])
        XCTAssertEqual(calls, 2) // window elapsed: refetched
        XCTAssertEqual(changed, []) // already confirmed — no new names
    }

    // MARK: - Connect-to-confirm path

    func testConnectConfirmConfirmsOwnership() {
        let tracker = ContinuityOwnershipTracker()

        let changed = tracker.confirmVisible(
            ["airpods 4 (anc)"],
            connectedTo: ["airpods 4 (anc)"]
        )
        XCTAssertEqual(changed, ["airpods 4 (anc)"])
        XCTAssertTrue(tracker.isOwned(name: "airpods 4 (anc)"))
    }

    func testConnectConfirmIsIdempotentPerConnectedSet() {
        let tracker = ContinuityOwnershipTracker()
        tracker.confirmVisible(["a"], connectedTo: ["a"])
        // Same connected set again → no new confirmations, no churn.
        let changed = tracker.confirmVisible(["a"], connectedTo: ["a"])
        XCTAssertEqual(changed, [])
    }

    func testConnectConfirmIgnoresUnseenNames() {
        // The system connected to a device, but it isn't among the visible
        // Continuity adverts — nothing to confirm.
        let tracker = ContinuityOwnershipTracker()
        let changed = tracker.confirmVisible([], connectedTo: ["mx master"])
        XCTAssertEqual(changed, [])
        XCTAssertFalse(tracker.isOwned(name: "mx master"))
    }

    func testEitherPathGrantsOwnership() {
        let tracker = ContinuityOwnershipTracker()
        ContinuityOwnershipTracker.pairedNamesProvider = { ["paired pods"] }

        // Connected-set confirms "connected pods"; paired list covers "paired pods".
        tracker.confirmVisible(["connected pods"], connectedTo: ["connected pods"])
        tracker.refreshPairedNamesIfStale(visibleNames: ["paired pods"])

        XCTAssertTrue(tracker.isOwned(name: "connected pods"))
        XCTAssertTrue(tracker.isOwned(name: "paired pods"))
        XCTAssertFalse(tracker.isOwned(name: "stranger pods"))
    }

    // MARK: - Owner-address path (the AirPods case)

    /// Regression: advert name `Mohit's AirPods - Find My` vs paired `AirPods 4 (ANC)`.
    func testAdvertNameMayDifferFromPairedName() {
        let tracker = ContinuityOwnershipTracker()
        // Paired list holds the model name, not the advert name.
        ContinuityOwnershipTracker.pairedNamesProvider = { ["airpods 4 (anc)"] }
        tracker.refreshPairedNamesIfStale(visibleNames: ["mohit's airpods - find my"])

        // Name matching alone still fails — this is the bug being fixed.
        XCTAssertFalse(tracker.isOwned(name: "mohit's airpods - find my"))
    }

    func testAddressSuffixGrantsOwnershipRegardlessOfName() {
        let tracker = ContinuityOwnershipTracker()
        ContinuityOwnershipTracker.pairedAddressSuffixProvider = { [[0x43, 0xB3, 0x52]] }
        tracker.refreshPairedAddressesIfStale()

        // Either candidate field may prove ownership.
        XCTAssertTrue(tracker.isOwnedByAddress([[0x43, 0xB3, 0x52]]))
        XCTAssertTrue(tracker.isOwnedByAddress([[0x90, 0x05, 0x6F], [0x43, 0xB3, 0x52]]))
        // A different device's suffix must not be trusted.
        XCTAssertFalse(tracker.isOwnedByAddress([[0x7E, 0x60, 0x0B]]))
        // Empty, malformed or absent suffixes never match.
        XCTAssertFalse(tracker.isOwnedByAddress([]))
        XCTAssertFalse(tracker.isOwnedByAddress([[0x43, 0xB3]]))
        XCTAssertFalse(tracker.isOwnedByAddress([[]]))
    }

    func testAddressRefreshIsCached() {
        let tracker = ContinuityOwnershipTracker()
        var calls = 0
        ContinuityOwnershipTracker.pairedAddressSuffixProvider = {
            calls += 1
            return [[0x43, 0xB3, 0x52]]
        }
        let now = Date()
        tracker.refreshPairedAddressesIfStale(now: now)
        tracker.refreshPairedAddressesIfStale(now: now.addingTimeInterval(30))
        XCTAssertEqual(calls, 1, "second refresh inside 60 s should be a no-op")

        tracker.refreshPairedAddressesIfStale(now: now.addingTimeInterval(61))
        XCTAssertEqual(calls, 2)
    }

    /// Zero means the address path has nothing to compare — the state that hid every AirPods advert.
    func testKnownAddressSuffixCountReflectsCache() {
        let tracker = ContinuityOwnershipTracker()
        ContinuityOwnershipTracker.pairedAddressSuffixProvider = { [] }
        XCTAssertEqual(tracker.knownAddressSuffixCount, 0, "nothing fetched yet")

        ContinuityOwnershipTracker.pairedAddressSuffixProvider = {
            [[0x43, 0xB3, 0x52], [0x7E, 0x60, 0x0B]]
        }
        tracker.refreshPairedAddressesIfStale()
        XCTAssertEqual(tracker.knownAddressSuffixCount, 2)
    }

    // MARK: - The gate predicate (the actual bug site)

    /// End-to-end shape of the 2026-10-23 regression, at the level the scanner runs it: the
    /// device's advert name does not match its paired name, so only the address can save it.
    func testGateShowsAirPodsMatchedByAddressOnly() {
        let tracker = ContinuityOwnershipTracker()
        ContinuityOwnershipTracker.pairedNamesProvider = { ["airpods 4 (anc)"] }
        ContinuityOwnershipTracker.pairedAddressSuffixProvider = { [[0x43, 0xB3, 0x52]] }
        tracker.refreshPairedAddressesIfStale()
        tracker.refreshPairedNamesIfStale(visibleNames: ["mohit's airpods - find my"])

        // Name match fails (different string), address match succeeds — the fix in one assertion.
        XCTAssertFalse(tracker.isOwned(name: "Mohit's AirPods - Find My"))
        XCTAssertTrue(tracker.isVisible(
            deviceID: "ble:\(UUID().uuidString)",
            name: "Mohit's AirPods - Find My",
            suffixes: [[0x43, 0xB3, 0x52]]
        ))
    }

    /// A stranger's AirPods carry a different owner's address and must stay hidden.
    func testGateHidesForeignDevice() {
        let tracker = ContinuityOwnershipTracker()
        ContinuityOwnershipTracker.pairedAddressSuffixProvider = { [[0x43, 0xB3, 0x52]] }
        tracker.refreshPairedAddressesIfStale()

        XCTAssertFalse(tracker.isVisible(
            deviceID: "ble:\(UUID().uuidString)",
            name: "Someone Else's AirPods",
            suffixes: [[0x7E, 0x60, 0x0B]]
        ))
    }

    /// The failure state that caused the bug: no suffixes known, name mismatch → hidden.
    func testGateHidesDeviceWhenAddressCacheIsEmpty() {
        let tracker = ContinuityOwnershipTracker()
        ContinuityOwnershipTracker.pairedAddressSuffixProvider = { [] }
        tracker.refreshPairedAddressesIfStale()

        XCTAssertEqual(tracker.knownAddressSuffixCount, 0)
        XCTAssertFalse(tracker.isVisible(
            deviceID: "ble:\(UUID().uuidString)",
            name: "Mohit's AirPods - Find My",
            suffixes: [[0x43, 0xB3, 0x52]]
        ), "no known suffixes + no name match = invisible (pre-fix behaviour)")
    }

    /// GATT/HID devices are paired by construction and must never be filtered.
    func testGatePassesNonBLEIDs() {
        let tracker = ContinuityOwnershipTracker()
        for id in ["gatt:ABC", "hid:00-11-22", "gatt:\(UUID().uuidString)"] {
            XCTAssertTrue(tracker.isVisible(deviceID: id, name: "Anything", suffixes: []),
                          "\(id) should bypass the gate")
        }
    }

    /// Name match alone still admits a device (the fallback path is retained, not removed).
    func testGateStillAdmitsByName() {
        let tracker = ContinuityOwnershipTracker()
        ContinuityOwnershipTracker.pairedNamesProvider = { ["magic mouse"] }
        tracker.refreshPairedNamesIfStale(visibleNames: [])

        XCTAssertTrue(tracker.isVisible(
            deviceID: "ble:\(UUID().uuidString)",
            name: "Magic Mouse",
            suffixes: []
        ))
    }

    /// Session B regression: bytes 13-15 rotated to bytes matching nothing, but 16-18 still held the
    /// paired AirPods' suffix. The gate must stay open on the second field alone.
    func testGateAcceptsWhenOnlyTheSecondSuffixFieldMatches() {
        let tracker = ContinuityOwnershipTracker()
        ContinuityOwnershipTracker.pairedAddressSuffixProvider = { [[0x5E, 0x30, 0x44]] }
        tracker.refreshPairedAddressesIfStale()

        XCTAssertTrue(tracker.isVisible(
            deviceID: "ble:\(UUID().uuidString)",
            name: "Mohit's AirPods - Find My",       // name does not match the paired name
            suffixes: [[0x90, 0x05, 0x6F], [0x5E, 0x30, 0x44]]
        ), "second field matching must be enough — this is what keeps AirPods visible")
    }
}
