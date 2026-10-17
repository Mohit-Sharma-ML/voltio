import XCTest
@testable import Voltio

/// Platform Health checks run clean on a healthy dev machine and return
/// well-formed results (Phase 2.3). Deliberately shallow: the checks touch
/// real IOKit/IOPS/FileSystem state, so on a broken machine some are
/// expected to fail — the contract is *structure*, not universal green.
@MainActor
final class PlatformHealthTests: XCTestCase {

    func testChecksAreWellFormed() {
        let checks = PlatformHealth.runChecks(bluetoothAccess: .scanning)
        XCTAssertEqual(checks.count, 4)
        XCTAssertEqual(Set(checks.map(\.id)), ["iokit", "powerSource", "bt", "appGroup"])
        // Every check carries a non-empty name and detail.
        XCTAssertTrue(checks.allSatisfy { !$0.name.isEmpty && !$0.detail.isEmpty })
    }

    func testBluetoothCheckReflectsAccess() {
        for access in [BluetoothAccess.scanning, .poweredOff, .needsPermission, .unavailable] {
            let check = PlatformHealth.runChecks(bluetoothAccess: access).first { $0.id == "bt" }
            XCTAssertEqual(check?.passed, access == .scanning)
        }
    }

    func testChecksEquatableByID() {
        let a = PlatformHealth.Check(id: "x", name: "X", passed: true, detail: "d1")
        let b = PlatformHealth.Check(id: "x", name: "Different", passed: false, detail: "d2")
        XCTAssertEqual(a, b) // id equality — ForEach stability matters more than content
    }
}
