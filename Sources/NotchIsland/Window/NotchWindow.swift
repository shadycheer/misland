import AppKit
import SwiftUI

enum IslandLayout {
    static let expandedWidth: CGFloat = 380
    static let expandedHeight: CGFloat = 168
    static let sideWidth: CGFloat = 30        // art / bars zone on each side of the notch
    static let collapsedWidth: CGFloat = 150  // no-notch floating pill
    static let collapsedHeight: CGFloat = 32
}

/// Resolved notch metrics for the active screen.
struct IslandGeometry {
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
}

/// Content view that only swallows mouse events inside `activeRect` (the visible
/// island). Everywhere else clicks fall through to the menu bar / desktop, so a
/// fixed full-size window never blocks anything.
final class PassthroughContainer: NSView {
    var activeRect: CGRect = .zero
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard activeRect.contains(local) else { return nil }
        return super.hitTest(point)
    }
}

final class NotchWindow: NSPanel {
    init(rootView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        contentView = rootView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Center horizontally on `screen`, top pinned to the screen top. Called once
    /// with the fixed (expanded) size — the island animates inside it.
    func place(on screen: NSScreen, size: CGSize) {
        let x = screen.frame.minX + (screen.frame.width - size.width) / 2
        let y = screen.frame.maxY - size.height
        setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
