import AppKit
import SwiftUI

enum IslandLayout {
    static let expandedWidth: CGFloat = 380
    static let expandedHeight: CGFloat = 168
    static let sideWidth: CGFloat = 42        // each wing beside the notch
    static let collapsedWidth: CGFloat = 220  // no-notch floating pill
    static let collapsedHeight: CGFloat = 32
}

/// Resolved notch metrics for the active screen.
struct IslandGeometry {
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
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

    /// Center horizontally on `screen` with the top pinned to the screen top, so
    /// the panel grows downward from the notch. Animated for the expand/collapse
    /// transition.
    func setFrameCentered(on screen: NSScreen, width: CGFloat, height: CGFloat, animated: Bool) {
        let x = screen.frame.minX + (screen.frame.width - width) / 2
        let y = screen.frame.maxY - height
        let frame = CGRect(x: x, y: y, width: width, height: height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.34
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true)
        }
    }
}
