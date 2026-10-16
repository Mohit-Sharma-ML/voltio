import Foundation
import UserNotifications

/// Delivers battery alerts as system notifications when the on-screen bubble
/// would be missed (Do Not Disturb, full-screen apps, user preference).
///
/// Runs on the main actor alongside the rest of the alert stack. Authorization
/// is requested lazily on first use so the app never prompts at launch.
@MainActor
final class NotificationSender {
    /// Lazy: `UNUserNotificationCenter.current()` traps when the process has no
    /// bundle context (e.g. SPM test runners), and constructing a sender must
    /// stay safe even where notifications are never used.
    private lazy var center = UNUserNotificationCenter.current()

    /// Whether the user enabled notification delivery in Settings.
    private let isEnabled: () -> Bool

    /// Cached authorization decision; avoids re-prompting after a denial.
    private var isAuthorized: Bool?

    init(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
    }

    /// Posts an alert as a system notification. Silent no-op when disabled,
    /// unauthorized, or the same alert fires repeatedly within a short window.
    func send(title: String, subtitle: String, category: String) {
        guard isEnabled() else { return }

        Task {
            guard await self.ensureAuthorized() else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = subtitle
            content.sound = .default
            // Same-thread replacement key so repeated low-battery crossings
            // update one notification instead of stacking up.
            content.threadIdentifier = "voltio.\(category)"

            let request = UNNotificationRequest(
                identifier: "voltio.\(category).\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await self.center.add(request)
        }
    }

    private func ensureAuthorized() async -> Bool {
        if let cached = isAuthorized { return cached }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            isAuthorized = granted
            return granted
        case .denied:
            isAuthorized = false
            return false
        @unknown default:
            return false
        }
    }
}
