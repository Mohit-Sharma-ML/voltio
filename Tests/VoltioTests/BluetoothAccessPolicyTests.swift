import XCTest
@testable import Voltio

/// What each Bluetooth access state offers the user.
///
/// Regression: `.restricted` (blocked by device-management policy) was folded into `.denied`, so a
/// managed Mac was told to "enable Voltio in System Settings" — a pane whose toggle is absent or
/// disabled. That is the same dead end this branch set out to remove, one layer deeper.
final class BluetoothAccessPolicyTests: XCTestCase {

    /// Only a real denial has something the user can change.
    func testOnlyDenialOffersSettingsLink() {
        XCTAssertTrue(BluetoothAccess.denied.offersSettingsLink)
        for state: BluetoothAccess in [
            .restricted, .awaitingPermission, .scanning, .poweredOff, .unavailable,
        ] {
            XCTAssertFalse(
                state.offersSettingsLink,
                "\(state) must not offer a Settings link — there is nothing there to change")
        }
    }

    /// The two states must not be interchangeable: that was the entire bug.
    func testRestrictedIsDistinctFromDenied() {
        XCTAssertNotEqual(BluetoothAccess.restricted, .denied)
    }

    /// A policy block is a stable state, not a transient one — it must survive equality checks used
    /// by the view layer to decide whether to re-render.
    func testRestrictedEqualityIsStable() {
        XCTAssertEqual(BluetoothAccess.restricted, .restricted)
        XCTAssertEqual(Set<BluetoothAccess>([.restricted, .restricted]).count, 1)
    }
}
