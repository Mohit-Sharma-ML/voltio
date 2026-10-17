import Foundation
import XCTest
@testable import Voltio

/// Ownership gating for Continuity (AirPods) BLE devices.
///
/// The Continuity path fires for ANY Apple device in radio range (RSSI ≥ -65
/// is proximity, not ownership) — a colleague's or stranger's AirPods would
/// otherwise appear in the Devices list. Devices are only shown once the
/// system has connected to them at least once (`connect-to-confirm`).
final class ContinuityOwnershipTests: XCTestCase {

    func testNormalizedNameTrimsAndLowercases() {
        XCTAssertEqual(BluetoothBatteryScanner.normalizedName("  Mohit's AirPods "), "mohit's airpods")
        XCTAssertEqual(BluetoothBatteryScanner.normalizedName("MX MASTER 3 B"), "mx master 3 b")
    }

    func testNormalizedNameNilForBlank() {
        XCTAssertNil(BluetoothBatteryScanner.normalizedName(nil))
        XCTAssertNil(BluetoothBatteryScanner.normalizedName("   "))
        XCTAssertNil(BluetoothBatteryScanner.normalizedName(""))
    }
}
