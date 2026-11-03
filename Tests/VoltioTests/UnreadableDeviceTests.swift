import PowerCore
import XCTest
@testable import Voltio

/// Connected Bluetooth devices whose battery no public API exposes must still be listed.
///
/// Regression: a paired JBL Wave Beam connected over Classic (HFP/A2DP) vanished from the Devices
/// list entirely. CoreBluetooth never sees Classic devices, so the BLE paths could not produce a
/// row — and silence reads as a bug rather than a limitation.
final class UnreadableDeviceTests: XCTestCase {

    func testConnectedClassicDeviceIsListedWithoutBattery() {
        let found = BluetoothBatteryScanner.unreadableDevices(
            connectedClassicNames: ["JBL WAVE BEAM"],
            readableNames: []
        )
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.name, "JBL WAVE BEAM")
        XCTAssertTrue(found.first?.batteries.isEmpty ?? false, "no level is known, so no reading")
        XCTAssertTrue(found.first?.isConnected ?? false)
        XCTAssertEqual(found.first?.id, "classic:jbl wave beam")
    }

    /// A device we *can* read must not also appear as an unreadable duplicate.
    func testReadableDeviceIsNotDuplicated() {
        let found = BluetoothBatteryScanner.unreadableDevices(
            connectedClassicNames: ["JBL WAVE BEAM", "AirPods"],
            readableNames: ["airpods"]
        )
        XCTAssertEqual(found.map(\.name), ["JBL WAVE BEAM"])
    }

    /// Name comparison is case- and whitespace-insensitive: the Classic stack and CoreBluetooth
    /// report the same device inconsistently.
    func testMatchingIgnoresCaseAndPadding() {
        let found = BluetoothBatteryScanner.unreadableDevices(
            connectedClassicNames: ["  jbl wave beam  "],
            readableNames: ["JBL WAVE BEAM"]
        )
        XCTAssertTrue(found.isEmpty)
    }

    /// Blank names (unnamed peripherals) must not create blank rows.
    func testBlankNamesAreIgnored() {
        let found = BluetoothBatteryScanner.unreadableDevices(
            connectedClassicNames: ["", "   "],
            readableNames: []
        )
        XCTAssertTrue(found.isEmpty)
    }

    /// The same device reported twice (possible across Classic/LE views) yields one row.
    func testDuplicateNamesCollapseToOneRow() {
        let found = BluetoothBatteryScanner.unreadableDevices(
            connectedClassicNames: ["JBL WAVE BEAM", "jbl wave beam"],
            readableNames: []
        )
        XCTAssertEqual(found.count, 1)
    }

    /// An unknown accessory still gets a kind so it renders with a sensible icon.
    func testKindIsClassified() {
        let found = BluetoothBatteryScanner.unreadableDevices(
            connectedClassicNames: ["JBL WAVE BEAM"],
            readableNames: []
        )
        XCTAssertEqual(found.first?.kind, .headphones)
    }
}
