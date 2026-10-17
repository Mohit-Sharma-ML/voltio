import AppKit
import SwiftUI
import PowerCore

/// Expanded-detail health cards: Battery Health, Temperature, Power &
/// Electrical, Power Flow, plus the shared card-title and stat-block
/// primitives (used by CapacityCards too). Extracted from MenuPanelView.swift
/// (Phase 1.2 of Docs/hardening-plan.md).
extension MenuPanelView {

    func healthCard(_ s: BatterySnapshot) -> some View {
        HStack(spacing: 12) {
            IconBadge(
                systemName: s.isHealthGood ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                tint: s.healthColor
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Battery Health").font(.callout.weight(.medium))
                    InfoButton(text: "Maximum charge your battery can now hold versus when it was new. Below ~80% macOS may recommend service.")
                    Spacer()
                    Text("\(s.healthPercent)%")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(s.healthColor)
                        .glow(s.healthColor, radius: 3)
                }
                FillBar(value: Double(s.healthPercent) / 100, tint: s.healthColor, height: 5)
                HStack {
                    Text(s.healthLabel).font(.caption).foregroundStyle(s.healthColor)
                    Spacer()
                    Text("\(s.cycleCount)/\(s.designCycleCount) cycles")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    func temperatureCard(_ s: BatterySnapshot) -> some View {
        let status = s.temperatureStatus
        return HStack(spacing: 12) {
            IconBadge(systemName: "thermometer.medium", tint: status.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Temperature").font(.callout.weight(.medium))
                    InfoButton(text: "Battery pack temperature. Sustained high temperatures speed up wear; under ~35°C is ideal.")
                }
                Text("\(status.label) · optimal performance")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(String(format: "%.1f°C", s.temperatureCelsius))
                    .font(.callout.weight(.bold))
                    .foregroundStyle(status.color)
                Text(String(format: "%.0f°F", s.temperatureFahrenheit))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    func powerCard(_ s: BatterySnapshot) -> some View {
        let verdict = s.electricalVerdict
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                cardTitle("Power & Electrical", systemImage: "bolt.fill", tint: .yellow)
                Spacer()
                InfoButton(text: "Live power draw, pack voltage and current. A down arrow means the battery is discharging; up means charging.")
            }
            HStack(alignment: .top) {
                statBlock("Power Usage", Format.watts(abs(s.powerWatts)))
                Spacer()
                statBlock("Voltage", String(format: "%.2f V", s.voltage), trailing: true)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("\(abs(s.amperage)) mA").font(.callout.weight(.semibold))
                        Image(systemName: s.currentDirectionIcon)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(verdict.color)
                    }
                }
                Spacer()
                Text(verdict.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(verdict.color)
            }
        }
        .card()
    }

    func flowCard(_ s: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                cardTitle("Power Flow", systemImage: "bolt.horizontal.circle.fill", tint: .teal)
                Spacer()
                InfoButton(text: "Where energy is moving right now — out of the battery to power the Mac, or into the battery while charging.")
            }
            PowerFlowView(flow: s.powerFlow)
        }
        .card()
    }

    func statBlock(_ label: String, _ value: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold))
        }
    }

    func cardTitle(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            IconBadge(systemName: systemImage, tint: tint, size: 24)
            Text(title).font(.callout.weight(.medium))
        }
    }

}
