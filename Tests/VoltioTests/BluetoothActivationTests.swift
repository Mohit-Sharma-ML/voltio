import CoreBluetooth
import PowerCore
import XCTest
@testable import Voltio

/// First-launch ordering: the Bluetooth TCC prompt must not fire before onboarding explains it.
///
/// Regression: `BatteryModel` is constructed in `VoltioApp.init`, earlier than the onboarding
/// window. Constructing `CBCentralManager` there raised the system permission prompt with no
/// context — the exact situation the onboarding step was added to prevent. The scanner now stays
/// dormant until told to activate.
@MainActor
final class BluetoothActivationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ContinuityOwnershipTracker.pairedNamesProvider = { nil }
        ContinuityOwnershipTracker.pairedAddressSuffixProvider = { [] }
    }

    override func tearDown() {
        ContinuityOwnershipTracker.pairedNamesProvider = ContinuityOwnershipTracker.fetchPairedNames
        ContinuityOwnershipTracker.pairedAddressSuffixProvider =
            ContinuityOwnershipTracker.pairedDeviceAddressSuffixes
        super.tearDown()
    }

    /// Constructing the scanner must not touch CoreBluetooth — that is what makes deferral possible.
    func testScannerDoesNotActivateOnInit() {
        XCTAssertFalse(BluetoothBatteryScanner().isActivated, "init must not create the central manager")
    }

    func testActivateCreatesCentralManager() {
        let scanner = BluetoothBatteryScanner()
        scanner.activate()
        XCTAssertTrue(scanner.isActivated)
    }

    func testActivateIsIdempotent() {
        let scanner = BluetoothBatteryScanner()
        scanner.activate()
        scanner.activate()
        XCTAssertTrue(scanner.isActivated)
    }

    /// A first launch holds the radio back until onboarding finishes.
    func testFreshInstallDefersBluetoothUntilActivated() {
        let model = makeModel(onboarded: false)
        XCTAssertFalse(model.isBluetoothActivated, "fresh install must not prompt before onboarding")

        model.activateBluetoothIfNeeded()
        XCTAssertTrue(model.isBluetoothActivated, "finishing onboarding brings the radio up")
    }

    /// The upgrade path: someone who onboarded before this change must not lose Bluetooth.
    func testExistingUserActivatesAtLaunch() {
        let model = makeModel(onboarded: true)
        XCTAssertTrue(model.isBluetoothActivated, "an existing user must not lose accessory battery")
    }

    /// Before activation there is no radio, but with permission already granted the app must not
    /// report `.unavailable` — that renders as "Radio unavailable — verify the Bluetooth
    /// entitlement", a false alarm during onboarding. Deferral means "not started yet".
    func testAccessBeforeActivationIsNeverUnavailableWhenGranted() throws {
        let scanner = BluetoothBatteryScanner()
        try XCTSkipUnless(
            CBCentralManager.authorization == .allowedAlways,
            "machine has not granted Bluetooth, cannot exercise the authorized-but-dormant path"
        )
        XCTAssertFalse(scanner.isActivated)
        XCTAssertNotEqual(scanner.access, .unavailable)
        XCTAssertEqual(scanner.access, .awaitingPermission)
    }

    // MARK: - Helpers

    private func makeModel(onboarded: Bool) -> BatteryModel {
        let suite = UserDefaults(suiteName: "test.bt.activation.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: suite)
        settings.hasCompletedOnboarding = onboarded
        let snapshot = BatterySnapshot(
            percentage: 50, isCharging: false, isPluggedIn: false, isFullyCharged: false,
            isLowPowerMode: false, minutesRemaining: 100, cycleCount: 10, designCycleCount: 1000,
            temperatureCelsius: 25, voltage: 11.6, amperage: 0, currentCapacitymAh: 4000,
            maxCapacitymAh: 8000, designCapacitymAh: 8800, adapterWatts: nil, adapterName: nil,
            systemPowerWatts: nil, batteryPowerWatts: nil, notChargingReason: nil
        )
        return BatteryModel(
            settings: settings,
            reader: FakeBatteryProvider(states: [snapshot]),
            widgetWriter: FakeWidgetPublisher(),
            chargeLimitReader: FakeChargeLimitReader(),
            startMonitors: false
        )
    }
}
