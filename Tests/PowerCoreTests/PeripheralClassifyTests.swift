import XCTest
@testable import PowerCore

final class PeripheralClassifyTests: XCTestCase {

    func testClassifiesPhones() {
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Mohit's iPhone"), .iphone)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Mohit's iPhone 16"), .iphone)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "IPHONE"), .iphone)
    }

    func testClassifiesTablets() {
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Mohit's iPad Pro"), .ipad)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "iPad"), .ipad)
    }

    func testClassifiesWatch() {
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Apple Watch"), .watch)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Mohit's Watch Ultra"), .watch)
    }

    func testClassifiesMacs() {
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Mohit's MacBook Pro"), .mac)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "iMac"), .mac)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Mac mini"), .mac)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Mac Studio"), .mac)
    }

    func testUnknownNamesFallBackToOther() {
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Toad II plus"), .other)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Hydra 10 5.3"), .other)
        XCTAssertEqual(PeripheralKind.classify(deviceName: ""), .other)
    }

    func testTabletTakesPrecedenceOverPhoneSubstring() {
        // "iPad" must not be misread; ensure ipad is checked independently of iphone.
        XCTAssertEqual(PeripheralKind.classify(deviceName: "iPad"), .ipad)
    }

    func testStableIdentityExcludesRotatingBLEAdverts() {
        func device(id: String) -> PeripheralDevice {
            PeripheralDevice(id: id, name: "x", kind: .other, source: .bluetooth, batteries: [])
        }
        // HID (Bluetooth address) and GATT (connected peripheral) ids are stable.
        XCTAssertTrue(device(id: "hid:00-11-22-33").hasStableIdentity)
        XCTAssertTrue(device(id: "gatt:1234-ABCD").hasStableIdentity)
        // BLE Continuity adverts rotate their UUID, so must not be remembered.
        XCTAssertFalse(device(id: "ble:1234-ABCD").hasStableIdentity)
    }
}

// MARK: - Real-device regression (Q3, verified live 2026-10-17)

extension PeripheralClassifyTests {

    /// Logitech MX Master 3 B — connected live during the Q3 investigation.
    /// Its name contains neither "mouse" nor any Apple keyword; both
    /// classification tables previously returned .other.
    func testLogitechMXMaster3B() {
        XCTAssertEqual(PeripheralKind.classify(deviceName: "MX Master 3 B"), .mouse)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "MX Master 3S"), .mouse)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "MX Anywhere 3"), .mouse)
    }

    func testGenericKeywordDevices() {
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Bluetooth Mouse"), .mouse)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Keys-To-Go"), .keyboard)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "K380 Keyboard"), .keyboard)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Beats Studio Buds"), .headphones)
        // Apple products still win (checked before the generic keywords):
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Apple Watch"), .watch)
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Mohit's iPhone"), .iphone)
        // Untouched names still degrade to .other
        XCTAssertEqual(PeripheralKind.classify(deviceName: "Hydra 10 5.3"), .other)
    }
}
