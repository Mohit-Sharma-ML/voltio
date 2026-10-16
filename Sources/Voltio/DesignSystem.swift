import SwiftUI

/// Shared visual language for the panel: card surfaces, badges, bars.
/// Kept flat and native — tint is used deliberately, not everywhere.
enum Theme {
    static let panelWidth: CGFloat = 320
    static let cornerRadius: CGFloat = 14
    static let cardCornerRadius: CGFloat = 12
}

// MARK: - Panel palette

extension Color {
    /// Panel background gradient (appearance-adaptive; dark values match the
    /// original fixed dark palette so the panel reads correctly in Light too).
    static let panelTop = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1)
            : NSColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1)
    })
    /// Panel background gradient (bottom of the gradient).
    static let panelBottom = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
            : NSColor(red: 0.90, green: 0.90, blue: 0.93, alpha: 1)
    })
    static let cardFill = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.09)
}

/// Subtle colored glow used sparingly on accent elements.
private struct Glow: ViewModifier {
    let color: Color
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.shadow(color: color.opacity(0.4), radius: radius)
    }
}

extension View {
    func glow(_ color: Color, radius: CGFloat = 8) -> some View {
        modifier(Glow(color: color, radius: radius))
    }
}

// MARK: - Card surface

private struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.cardStroke)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardSurface()) }
}

// MARK: - Reusable pieces

/// A circular tinted badge holding an SF Symbol.
struct IconBadge: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.18)))
            .glow(tint, radius: 3)
    }
}

/// A small tappable "info" affordance that reveals an explanation popover.
struct InfoButton: View {
    let text: String
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(width: 230)
        }
    }
}

/// Uppercase section label.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// Rounded progress capsule with a tinted fill.
struct FillBar: View {
    let value: Double           // 0...1
    var tint: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// A small labeled statistic used in horizontal groups.
struct StatTile: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A status pill (icon + text) tinted by battery state.
struct StatusPill: View {
    let text: String
    let systemName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.18)))
        .glow(tint, radius: 4)
    }
}

/// A circular charge gauge with the percentage in the center — the hero centerpiece.
struct BatteryRing: View {
    let level: Double           // 0...1
    let percentage: Int
    let tint: Color
    let isCharging: Bool

    var size: CGFloat = 150
    private var lineWidth: CGFloat { size * 0.08 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, min(1, level)))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [tint.opacity(0.55), tint]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .glow(tint, radius: 5)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(percentage)")
                        .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: size * 0.12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.09, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.top, 2)
                }
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.5), value: level)
    }
}
