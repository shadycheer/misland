import AppKit
import SwiftUI

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

    /// Position centered against the notch / top of the given screen.
    func reposition(on screen: NSScreen, size: CGSize) {
        let notch = NotchGeometry.notchSize(
            forScreenWidth: screen.frame.width,
            safeAreaTop: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )
        let layout = NotchGeometry.layout(
            screenWidth: screen.frame.width,
            screenTop: screen.frame.maxY,
            notchWidth: notch.width,
            notchHeight: notch.height,
            collapsedSize: size
        )
        setFrame(CGRect(
            x: screen.frame.minX + layout.collapsedFrame.minX,
            y: layout.collapsedFrame.minY - (240 - size.height),
            width: max(size.width, 430),
            height: 240
        ), display: true)
    }
}
