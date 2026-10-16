import AppKit
import SwiftUI

/// Abstraction over the screen-edge glow so `AlertManager`'s decision logic can
/// be exercised in tests without flashing a real window.
@MainActor
protocol GlowPresenting: AnyObject {
    func flash(color: NSColor, intensity: CGFloat)
}

extension GlowOverlayController: GlowPresenting {}

/// Flashes a colored glow around the edges of the main screen. The window is a
/// click-through, non-activating panel above normal windows, so it never steals
/// focus or interrupts the user.
@MainActor
final class GlowOverlayController {
    private var window: NSPanel?

    func flash(color: NSColor, intensity: CGFloat = 1) {
        guard intensity > 0, let screen = NSScreen.main else { return }

        window?.orderOut(nil)

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.contentView = NSHostingView(
            rootView: EdgeGlow(color: Color(nsColor: color), intensity: intensity)
        )
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        window = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 1
        }

        // Hold, then fade out and dispose. The Task inherits this @MainActor
        // context, so the panel ops stay on the main thread without GCD closures.
        Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(1.8))
            guard let panel else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.6
                panel.animator().alphaValue = 0
            }
            panel.orderOut(nil)
            if self?.window === panel { self?.window = nil }
        }
    }
}

/// A soft glow hugging the screen edges, fading toward the center. `intensity`
/// scales the thickness/opacity (driven by the "Screen Edge Glow" preference).
private struct EdgeGlow: View {
    let color: Color
    var intensity: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(color, lineWidth: 26 * intensity)
                .blur(radius: 32)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(color.opacity(0.75), lineWidth: 9 * intensity)
                .blur(radius: 9)
        }
        .opacity(min(1, Double(intensity)))
        .padding(12)
        .ignoresSafeArea()
    }
}
