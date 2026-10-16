import AppKit
import Observation
import SwiftUI

/// Drives the bubble's enter/exit animation. Mutating `shown` inside
/// `withAnimation` makes the SwiftUI bubble spring in/out smoothly.
@MainActor
@Observable
final class BubblePresenter {
    var shown = false
}

/// Abstraction over the on-screen alert bubble so `AlertManager`'s decision
/// logic can be exercised in tests without creating real windows.
@MainActor
protocol AlertBubblePresenting: AnyObject {
    func show(_ style: AlertBubbleController.Style)
}

extension AlertBubbleController: AlertBubblePresenting {}

/// Presents on-screen alert "bubbles": a floating pill that springs
/// in at the top or center of the screen, shows the battery state, and either
/// auto-dismisses or stays until the user clicks ✕. Implemented as a borderless,
/// non-activating panel so it never steals focus from the foreground app.
@MainActor
final class AlertBubbleController {
    static let shared = AlertBubbleController()

    private let presenter = BubblePresenter()

    /// Everything needed to render one bubble.
    struct Style {
        var title: String
        var subtitle: String
        var systemImage: String
        var color: Color
        var position: AlertPosition
        var persistent: Bool
        /// Visual scale from the "Alert Bubble Size" preference.
        var scale: CGFloat = 1
        /// Seconds a non-persistent bubble stays on screen before auto-dismissing.
        var holdSeconds: Double = 3
    }

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    /// Outer transparent margin baked into the hosted view so the bubble's glow
    /// and shadow have room to render inside the panel bounds.
    private let margin: CGFloat = 26
    private let baseWidth: CGFloat = 320
    private let baseHeight: CGFloat = 64

    func show(_ style: Style) {
        dismissTask?.cancel()
        hideTask?.cancel()

        // Start hidden so the freshly-built view springs in from `onAppear`.
        presenter.shown = false

        let root = AlertBubbleView(
            style: style, margin: margin, bubbleWidth: baseWidth, bubbleHeight: baseHeight,
            presenter: presenter
        ) { [weak self] in self?.dismiss() }

        let size = contentSize(style.scale)
        let panel = panel ?? makePanel(size: size)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.setContentSize(size)
        positionPanel(panel, for: style.position, size: size)

        // The panel is fully opaque; the SwiftUI content owns the fade/slide.
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        if !style.persistent {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(style.holdSeconds))
                guard !Task.isCancelled else { return }
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        hideTask?.cancel()
        guard let panel else { return }

        withAnimation(.easeIn(duration: 0.2)) { presenter.shown = false }
        hideTask = Task { [weak panel] in
            try? await Task.sleep(for: .milliseconds(230))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
        }
    }

    // MARK: - Panel plumbing

    private func contentSize(_ scale: CGFloat) -> NSSize {
        NSSize(
            width: (baseWidth + margin * 2) * scale,
            height: (baseHeight + margin * 2) * scale
        )
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        return panel
    }

    private func positionPanel(_ panel: NSPanel, for position: AlertPosition, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let x = area.midX - size.width / 2
        let y: CGFloat
        switch position {
        case .center: y = area.midY - size.height / 2
        case .top:    y = area.maxY - size.height + (margin * panelScale(size)) - 8
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Recover the applied scale from a content size (for top-edge insetting).
    private func panelScale(_ size: NSSize) -> CGFloat {
        (baseWidth + margin * 2) > 0 ? size.width / (baseWidth + margin * 2) : 1
    }
}

/// The pill itself. Dark translucent capsule with a colored border + glow, a
/// battery glyph, two lines of text, and a close button. Rendered at its base
/// size, then scaled by the size preference.
private struct AlertBubbleView: View {
    let style: AlertBubbleController.Style
    let margin: CGFloat
    let bubbleWidth: CGFloat
    let bubbleHeight: CGFloat
    let presenter: BubblePresenter
    let onClose: () -> Void

    var body: some View {
        let total = CGSize(
            width: (bubbleWidth + margin * 2) * style.scale,
            height: (bubbleHeight + margin * 2) * style.scale
        )
        return pill
            .padding(margin)
            .scaleEffect(style.scale)
            .frame(width: total.width, height: total.height)
            .scaleEffect(presenter.shown ? 1 : 0.92, anchor: .top)
            .offset(y: presenter.shown ? 0 : -22)
            .opacity(presenter.shown ? 1 : 0)
            .environment(\.colorScheme, .dark)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                    presenter.shown = true
                }
            }
    }

    private var pill: some View {
        HStack(spacing: 12) {
            iconBadge

            VStack(alignment: .leading, spacing: 1) {
                Text(style.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(style.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 6)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(width: bubbleWidth, height: bubbleHeight)
        .background(bubbleBackground)
        .overlay(runningBorder)
        .shadow(color: style.color.opacity(0.35), radius: 16)
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }

    /// Glyph inside a soft colored disc, matching the in-panel icon badges.
    private var iconBadge: some View {
        ZStack {
            Circle().fill(style.color.opacity(0.18))
            Image(systemName: style.systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(style.color)
                .shadow(color: style.color.opacity(0.6), radius: 4)
        }
        .frame(width: 34, height: 34)
        .overlay(Circle().strokeBorder(style.color.opacity(0.35), lineWidth: 1))
    }

    private var bubbleBackground: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                // Gradient tint over the material: keeps the glassy depth of
                // the blur while darkening the base so white text stays legible.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.13, green: 0.13, blue: 0.15).opacity(0.85),
                                     Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.9)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .overlay(Capsule(style: .continuous).strokeBorder(style.color.opacity(0.22), lineWidth: 1))
    }

    /// A glowing highlight that continuously "runs" around the pill's edge.
    private var runningBorder: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((t * 115).truncatingRemainder(dividingBy: 360))
            Capsule(style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: style.color.opacity(0.0), location: 0.55),
                            .init(color: style.color.opacity(0.7), location: 0.74),
                            .init(color: .white.opacity(0.95), location: 0.82),
                            .init(color: style.color.opacity(0.7), location: 0.90),
                            .init(color: .clear, location: 1.00),
                        ]),
                        center: .center,
                        angle: angle
                    ),
                    lineWidth: 2
                )
                .shadow(color: style.color.opacity(0.85), radius: 4)
        }
    }

}
