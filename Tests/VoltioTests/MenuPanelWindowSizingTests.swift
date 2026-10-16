import AppKit
import Testing
@testable import Voltio

@MainActor
@Suite("Menu panel window sizing")
struct MenuPanelWindowSizingTests {
    @Test("Collapsing shrinks the window without moving its top edge")
    func collapsePreservesTopEdge() {
        let window = makeWindow()
        let top = window.frame.maxY
        let left = window.frame.minX

        MenuPanelWindowSizer.resize(window, to: CGSize(width: 320, height: 398))

        #expect(window.frame.height == 398)
        #expect(window.frame.width == 320)
        #expect(window.frame.maxY == top)
        #expect(window.frame.minX == left)
    }

    @Test("Repeated expansion and collapse leave no stale window height")
    func repeatedResize() {
        let window = makeWindow()
        let top = window.frame.maxY

        for height: CGFloat in [398, 957, 398, 957, 398, 398] {
            MenuPanelWindowSizer.resize(window, to: CGSize(width: 320, height: height))
            #expect(window.frame.height == height)
            #expect(window.frame.maxY == top)
        }
    }

    @Test("Unmeasured content cannot collapse the window to zero")
    func zeroSizeIsIgnored() {
        let window = makeWindow()
        let initial = window.frame

        MenuPanelWindowSizer.resize(window, to: .zero)

        #expect(window.frame == initial)
    }

    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 320, height: 957),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }
}