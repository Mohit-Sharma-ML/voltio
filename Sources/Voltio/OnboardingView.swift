import SwiftUI

/// First-launch onboarding: a compact welcome window that explains what Voltio
/// does, how alerts work, and where to find settings. Shown once; the
/// `hasCompletedOnboarding` flag in `AppSettings` gates re-showing it.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            hero
            VStack(alignment: .leading, spacing: 18) {
                step(
                    icon: "menubar.dock.rectangle",
                    title: "Lives in your menu bar",
                    detail: "Click the battery icon any time for health, temperature, power draw, and connected accessories."
                )
                step(
                    icon: "bell.badge",
                    title: "Alerts that fit your workflow",
                    detail: "Low and charged alerts appear as an on-screen bubble with optional glow and sound. Enable system notifications in Settings → Alerts to catch them even in full-screen apps."
                )
                step(
                    icon: "slider.horizontal.3",
                    title: "Tune everything",
                    detail: "Icon style, refresh rate, bubble size, per-device alerts — all in Settings. Open it from the menu-bar panel's gear button."
                )
            }
            .padding(24)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Get Started") {
                    settings.hasCompletedOnboarding = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(width: 420, height: 480)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.batteryblock.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.green.gradient)
                .padding(.top, 28)
            Text("Welcome to Voltio")
                .font(.title2.weight(.semibold))
            Text("A precise window into your Mac's battery.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }

    private func step(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
