import AppKit
import SwiftUI

enum IslandLayout {
    static let expandedWidth: CGFloat = 372
    static let expandedHeight: CGFloat = 168
    static let collapsedWidth: CGFloat = 200
    static let collapsedHeight: CGFloat = 32
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

    /// Center the panel horizontally on the screen and pin its top to the very
    /// top of the screen, so the (black) content fuses with the notch above it.
    func place(on screen: NSScreen, contentHeight: CGFloat) {
        let w = IslandLayout.expandedWidth
        let h = contentHeight
        let x = screen.frame.minX + (screen.frame.width - w) / 2
        let y = screen.frame.maxY - h
        setFrame(CGRect(x: x, y: y, width: w, height: h), display: true)
    }
}
