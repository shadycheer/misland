import AppKit
import SwiftUI

enum IslandLayout {
    static let expandedWidth: CGFloat = 380
    static let expandedHeight: CGFloat = 180
    static let browserHeight: CGFloat = 392    // taller panel while the playlist browser is open
    static let noNotchStripHeight: CGFloat = 28 // top control strip height on notch-less screens
    static let sideWidth: CGFloat = 42        // art / bars zone on each side of the notch
    static let collapsedWidth: CGFloat = 220  // no-notch pill (art + title + bars)
    static let collapsedHeight: CGFloat = 32
}

/// Resolved notch metrics for the active screen.
struct IslandGeometry {
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    /// Menu-bar height of the screen — the collapsed height on notch-less
    /// displays, so the pill sits inside the bar instead of poking below it.
    var barHeight: CGFloat = 24
}

/// Container view. Click-through is handled precisely by the app's global mouse
/// monitor toggling `window.ignoresMouseEvents`, so this just hosts content.
final class PassthroughContainer: NSView {}

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
        ignoresMouseEvents = true  // click-through by default; the app enables it only over the island
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
