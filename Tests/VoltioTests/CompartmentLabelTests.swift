import XCTest
import PowerCore
@testable import Voltio

/// Compartment labels: one pod in the case used to read as the whole device's charge.
final class CompartmentLabelTests: XCTestCase {

    /// Pin the deep link — a typo fails silently at runtime.
    func testBluetoothPrivacyDeepLinkTargetsThePrivacyPane() throws {
        let url = try XCTUnwrap(BluetoothPrivacySettings.url)
        XCTAssertEqual(url.scheme, "x-apple.systempreferences")
        XCTAssertTrue(url.absoluteString.contains("com.apple.preference.security"))
        XCTAssertTrue(url.absoluteString.contains("Privacy_Bluetooth"))
    }

    func testShortLabels() {
        XCTAssertEqual(compartmentShortLabel("Left"), "L")
        XCTAssertEqual(compartmentShortLabel("Right"), "R")
        XCTAssertEqual(compartmentShortLabel("Case"), "Case")
    }

    func testNilLabelStaysEmpty() {
        // A single-cell reading has no compartment name; "" beats a stray marker.
        XCTAssertEqual(compartmentShortLabel(nil), "")
    }

    func testUnknownLabelPassesThrough() {
        XCTAssertEqual(compartmentShortLabel("Main"), "Main")
    }

    func testReadingShortLabelMatchesFunction() {
        let reading = BatteryReading(id: "left", label: "Left", percent: 40, isCharging: false)
        XCTAssertEqual(reading.shortLabel, "L")
    }
}
