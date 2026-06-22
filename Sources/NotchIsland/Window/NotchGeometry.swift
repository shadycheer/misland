import CoreGraphics

struct NotchLayout: Equatable {
    let hasNotch: Bool
    let collapsedFrame: CGRect
}

enum NotchGeometry {
    /// Coordinates use a bottom-left origin (AppKit screen space). `screenTop`
    /// is the y of the top edge of the usable area (== screen height here).
    static func layout(
        screenWidth: CGFloat, screenTop: CGFloat,
        notchWidth: CGFloat, notchHeight: CGFloat,
        collapsedSize: CGSize
    ) -> NotchLayout {
        let hasNotch = notchWidth > 0 && notchHeight > 0
        let x = (screenWidth - collapsedSize.width) / 2
        let y = screenTop - collapsedSize.height
        return NotchLayout(
            hasNotch: hasNotch,
            collapsedFrame: CGRect(x: x, y: y, width: collapsedSize.width, height: collapsedSize.height)
        )
    }

    /// Resolve notch dimensions for a screen from AppKit APIs.
    /// `safeAreaTop > 0` is THE notch signal (notch height). The auxiliary areas
    /// give the exact width when available; otherwise estimate it — some configs
    /// don't expose them, and a missing width must not flip "has notch" to false.
    static func notchSize(forScreenWidth width: CGFloat,
                          safeAreaTop: CGFloat,
                          leftArea: CGRect?, rightArea: CGRect?) -> CGSize {
        guard safeAreaTop > 0 else { return .zero }
        let notchWidth: CGFloat
        if let left = leftArea, let right = rightArea {
            notchWidth = max(0, width - left.width - right.width)
        } else {
            notchWidth = 200 // typical MacBook notch width when aux areas are unavailable
        }
        return CGSize(width: notchWidth, height: safeAreaTop)
    }
}
