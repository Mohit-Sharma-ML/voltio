import AppKit
import SwiftUI
import PowerCore

/// Capacity, charging-condition, charge-limit-awareness, and hardware-specs
/// cards. Extracted from MenuPanelView.swift.
extension MenuPanelView {

    func capacityCard(_ s: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                cardTitle("Capacity", systemImage: "battery.100percent", tint: .green)
                InfoButton(text: "Measured pack charge: remaining vs. the most it can hold today (full charge) vs. original factory capacity (design). The ring at the top shows macOS's charge estimate, which can sit a few points above or below the pack's measured ratio while charging or discharging.")
                Spacer()
                Text("mAh").font(.caption2).foregroundStyle(.secondary)
            }
            capacityBar(s)
            HStack(alignment: .top) {
                capacityStat("Remaining", s.currentCapacitymAh, .green.adaptiveTextTint(activeScheme),
                             note: "\(s.packChargePercent)% of full")
                Spacer()
                capacityStat("Full charge", s.maxCapacitymAh, .primary)
                Spacer()
                capacityStat("Design", s.designCapacitymAh, .secondary)
            }
        }
        .card()
    }

    func capacityBar(_ s: BatterySnapshot) -> some View {
        let scheme = activeScheme
        return GeometryReader { geo in
            let width = geo.size.width
            let design = Double(s.designCapacitymAh)
            let fullFraction = design > 0 ? Double(s.maxCapacitymAh) / design : 0
            let currentFraction = design > 0 ? Double(s.currentCapacitymAh) / design : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(scheme == .light ? 0.14 : 0.10))
                Capsule().fill(Color.primary.opacity(scheme == .light ? 0.26 : 0.20))
                    .frame(width: width * min(1, fullFraction))
                Capsule().fill(Color.green)
                    .frame(width: width * min(1, currentFraction))
            }
        }
        .frame(height: 8)
    }

    /// Charging-condition note: why a plugged-in battery isn't charging, plus a
    /// Low Power Mode chip. Collapses into the expanded detail cards.
    @ViewBuilder
    func batteryConditionCard(_ s: BatterySnapshot) -> some View {
        if s.isLowPowerMode || s.notChargingReason != nil {
            HStack(spacing: 12) {
                IconBadge(
                    systemName: s.isLowPowerMode ? "bolt.badge.a" : "pause.circle.fill",
                    tint: .yellow
                )
                VStack(alignment: .leading, spacing: 2) {
                    if s.isLowPowerMode {
                        Text("Low Power Mode is on").font(.callout.weight(.medium))
                    }
                    if let reason = s.notChargingReason {
                        Text("Not charging — \(reason.explanation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            .card()
        }
        chargeLimitCard(s)
    }

    /// Native charge-limit awareness: shows the macOS-configured Charge Limit
    /// (System Settings → Battery) when one is set, with a deep-link button.
    /// Read-only — Voltio deliberately doesn't (and can't) set the limit;
    /// firmware charge-limit writes are entitlement-gated on current macOS.
    @ViewBuilder
    func chargeLimitCard(_ s: BatterySnapshot) -> some View {
        if let label = s.chargeLimitLabel(limit: model.chargeLimit) {
            HStack(spacing: 12) {
                IconBadge(systemName: "gauge.with.needle", tint: .mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.callout.weight(.medium))
                    Text("Set in System Settings → Battery")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Battery settings")
            }
            .card()
        }
    }

    /// Hardware identity: pack serial number and manufacture date. Missing
    /// fields are simply omitted — many Macs don't expose both.
    @ViewBuilder
    func specsCard(_ s: BatterySnapshot) -> some View {
        if s.serialNumber != nil || s.manufactureDate != nil {
            HStack(spacing: 12) {
                IconBadge(systemName: "info.circle", tint: .blue)
                VStack(alignment: .leading, spacing: 2) {
                    if let serial = s.serialNumber {
                        HStack(spacing: 6) {
                            Text("Serial").font(.caption).foregroundStyle(.secondary)
                            Text(serial)
                                .font(.caption.weight(.medium).monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    if let made = s.manufactureDate {
                        HStack(spacing: 6) {
                            Text("Made").font(.caption).foregroundStyle(.secondary)
                            Text(made.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption.weight(.medium))
                        }
                    }
                }
                Spacer()
            }
            .card()
        }
    }

    func capacityStat(_ label: String, _ value: Int, _ tint: Color, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(Format.number(value))
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

}
