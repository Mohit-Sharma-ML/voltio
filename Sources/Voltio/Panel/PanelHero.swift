import AppKit
import SwiftUI
import PowerCore

/// The panel hero: charge ring, status pill, time line, plus the compact
/// charge-management hint line. Extracted from MenuPanelView.swift
/// internal so the container in the
/// core file can compose it.
extension MenuPanelView {

    /// Compact, always-visible line explaining macOS's charging management:
    /// the native Charge Limit when set, or a one-word pointer to the hold
    /// state shown in the status pill ("Paused by macOS"). Hidden when macOS
    /// isn't managing charging at all.
    @ViewBuilder
    func chargeManagementHint(_ s: BatterySnapshot) -> some View {
        let limitLabel = s.chargeLimitLabel(limit: model.chargeLimit)
        if let limitLabel {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.needle")
                    .font(.caption2)
                    .foregroundStyle(.mint)
                Text(limitLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if s.isPausedByMacOS {
            HStack(spacing: 5) {
                Image(systemName: "bolt.pause.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text("macOS is holding the charge (Optimized Charging)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if s.isPluggedIn, s.isFullyCharged {
            // 100% on AC with no limit/hold active: tell the user no limit
            // is configured — the natural moment to discover the feature.
            // Tappable: opens Battery settings (where the limit lives).
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.needle")
                        .font(.caption2)
                        .foregroundStyle(.mint)
                    Text("No charge limit set — set one in Battery settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .underline()
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Hero

    func hero(_ s: BatterySnapshot) -> some View {
        VStack(spacing: 12) {
            BatteryRing(
                level: Double(s.percentage) / 100,
                percentage: s.percentage,
                tint: s.stateColor,
                isCharging: s.isCharging
            )

            StatusPill(text: s.statusText, systemName: s.statusIcon, tint: s.stateColor)

            if let minutes = s.minutesRemaining {
                Text(timeText(s, minutes: minutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.cardFill)
                RadialGradient(
                    colors: [s.stateColor.opacity(0.16), .clear],
                    center: .center,
                    startRadius: 6,
                    endRadius: 160
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(s.stateColor.opacity(0.20))
        )
    }

    func timeText(_ s: BatterySnapshot, minutes: Int) -> String {
        s.isCharging
            ? "Full in \(Format.minutes(minutes))"
            : "\(Format.minutes(minutes)) remaining"
    }

}
