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
    static func notchSize(forScreenWidth width: CGFloat,
                          safeAreaTop: CGFloat,
                          leftArea: CGRect?, rightArea: CGRect?) -> CGSize {
        guard safeAreaTop > 0, let left = leftArea, let right = rightArea else {
            return .zero
        }
        let notchWidth = width - left.width - right.width
        return CGSize(width: max(0, notchWidth), height: safeAreaTop)
    }
}
