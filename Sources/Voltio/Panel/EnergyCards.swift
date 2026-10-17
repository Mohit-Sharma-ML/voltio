import AppKit
import SwiftUI
import PowerCore

/// Energy Today and per-app attribution cards, plus the updated/refresh line.
/// Extracted from MenuPanelView.swift (Phase 1.2 of Docs/hardening-plan.md);
/// reads model + settings, both internal.
extension MenuPanelView {

    /// Today's accumulated energy (trapezoid integral over sampled power) and
    /// the smoothed live draw. Appears once two samples exist; hidden entirely
    /// when the ⇧⌘E toggle (or its Settings row) turns it off.
    @ViewBuilder
    var energyCard: some View {
        if settings?.showEnergyCard != false, let today = model.todayEnergy {
            HStack(spacing: 12) {
                IconBadge(systemName: "gauge.with.dots.needle.33percent", tint: .teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Energy Today").font(.callout.weight(.medium))
                    Text("Sampled over \(Int(today.sampledMinutes.rounded())) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.2f Wh", today.wattHours))
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.teal)
                    if let watts = model.smoothedPowerWatts {
                        Text(String(format: "%.1f W avg", watts))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .card()
        }
    }

    /// Per-app energy attribution, sampled only while on battery. Hidden until
    /// the first two sampler ticks produce data; when the OS energy counters
    /// are unavailable the figures carry a CPU-share estimate disclosure.
    @ViewBuilder
    var energyAppsCard: some View {
        if settings?.showEnergyApps != false, !model.energyApps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    IconBadge(systemName: "bolt.horizontal.circle", tint: .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apps Using Energy").font(.callout.weight(.medium))
                        Text(model.energyAppsMeasured
                             ? "Sampled over the last few minutes"
                             : "Estimated from CPU share")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(model.energyApps.prefix(5)) { app in
                    HStack(spacing: 8) {
                        Text(app.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(app.method == .cpuShare ? "~" : "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f W", app.watts))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
                if model.energyApps.count > 5 {
                    Text("+\(model.energyApps.count - 5) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }

    @ViewBuilder
    var updatedLine: some View {
        if let updated = model.lastUpdated {
            HStack(spacing: 4) {
                Text("Updated \(Format.relative(updated))")
                Text("·")
                Button { model.refresh() } label: {
                    Text("Refresh now").foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
    }

}
