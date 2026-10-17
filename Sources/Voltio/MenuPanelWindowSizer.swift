import AppKit
import SwiftUI
import PowerCore

struct MenuPanelWindowSizer: NSViewRepresentable {
    let contentSize: CGSize

    func makeNSView(context: Context) -> SizingView {
        SizingView()
    }

    func updateNSView(_ view: SizingView, context: Context) {
        view.contentSize = contentSize
    }

    static func resize(_ window: NSWindow, to contentSize: CGSize) {
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        let size = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size
        let current = window.frame
        guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else {
            return
        }
        window.setFrame(
            CGRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    final class SizingView: NSView {
        var contentSize: CGSize = .zero {
            didSet { scheduleResize() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleResize()
        }

        private func scheduleResize() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window else { return }
                MenuPanelWindowSizer.resize(window, to: contentSize)
            }
        }
    }
}

