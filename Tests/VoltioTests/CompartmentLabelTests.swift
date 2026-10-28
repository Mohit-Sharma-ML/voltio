import XCTest
import PowerCore
@testable import Voltio

/// Presentation rules for device compartment labels.
///
/// Regression context (2026-10-23): with one pod in its case only the worn pod
/// advertises, so the row showed a bare percentage that read as the whole
/// device's charge ("AirPods 4 (ANC) 23%" while that was the left pod alone).
/// The headline now names the compartment until a second one reports.
final class CompartmentLabelTests: XCTestCase {

    /// The deep link is a string, so a typo or a reworded URL fails silently at
    /// runtime — the button would just do nothing. Pin the pieces the user needs
    /// (security pane + Bluetooth anchor) so drift is a test failure.
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
        // A single-cell reading has no compartment name; rendering "nil" or a
        // stray marker would be worse than nothing.
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
