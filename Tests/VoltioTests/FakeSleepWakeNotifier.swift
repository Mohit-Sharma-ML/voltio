import Foundation
@testable import Voltio

/// Fake sleep/wake notifier for `BatteryModel` characterization tests
/// (Q1 of the hardening plan's fix queue). Tests drive the transitions
/// with `simulateSleep()` / `simulateWake()` — no IOKit, no real sleep.
@MainActor
final class FakeSleepWakeNotifier: SleepWakeNotifying {
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?
    private(set) var startCount = 0

    func start() {
        startCount += 1
    }

    /// Test-side trigger: fire the sleep handler (as the observer would
    /// after acknowledging kIOMessageSystemWillSleep).
    func simulateSleep() {
        onSleep?()
    }

    /// Test-side trigger: fire the wake handler (as the observer would on
    /// kIOMessageSystemHasPoweredOn — full wake only).
    func simulateWake() {
        onWake?()
    }
}
