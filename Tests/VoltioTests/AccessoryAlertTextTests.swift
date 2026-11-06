import PowerCore
import XCTest
@testable import Voltio

/// Accessory low-battery alert copy.
///
/// Regression: with one pod in its case only that pod reports, so the alert read
/// "23% remaining" for a device that was otherwise fully charged. The panel was fixed to
/// prefix the compartment; the notification kept the misleading framing.
final class AccessoryAlertTextTests: XCTestCase {

    private func device(_ labels: [String], percents: [Int], kind: PeripheralKind = .airpods)
        -> PeripheralDevice
    {
        PeripheralDevice(
            id: "ble:x", name: "Mohit's AirPods - Find My", kind: kind, source: .bluetooth,
            batteries: zip(labels, percents).map {
                BatteryReading(id: $0, label: $0, percent: $1, isCharging: false)
            }
        )
    }

    /// One pod reporting must name the compartment, matching the panel's `L 23%`.
    func testLoneCompartmentIsNamed() {
        let text = accessoryAlertText(for: device(["Left"], percents: [23]))
        XCTAssertEqual(text.title, "Mohit's AirPods - Find My Low")
        XCTAssertTrue(text.subtitle.hasPrefix("Left 23%"), "got: \(text.subtitle)")
        XCTAssertFalse(text.subtitle.hasPrefix("23%"), "must not read as the whole device")
    }

    /// With both pods reporting, the headline number is the lower of them — no prefix needed.
    func testBothCompartmentsStayUnadorned() {
        let text = accessoryAlertText(for: device(["Left", "Right"], percents: [18, 74]))
        XCTAssertTrue(text.subtitle.hasPrefix("18%"), "got: \(text.subtitle)")
    }

    /// A single-battery device (AirPods Max, a mouse) is never labelled.
    func testSingleBatteryDeviceStaysUnadorned() {
        let max = device(["Left"], percents: [23], kind: .airpodsMax)
        XCTAssertTrue(accessoryAlertText(for: max).subtitle.hasPrefix("23%"))
    }

    /// Case-only reading is also a lone compartment and must be named.
    func testCaseOnlyIsNamed() {
        let text = accessoryAlertText(for: device(["Case"], percents: [9]))
        XCTAssertTrue(text.subtitle.hasPrefix("Case 9%"), "got: \(text.subtitle)")
    }
}
