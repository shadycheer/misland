import SwiftUI

/// Dynamic-Island-style shape: the top edge spans full width and the top
/// corners curve *inward* (concave) so the island looks like it flows out of
/// the notch / menu bar above it; the bottom corners are generously rounded.
struct NotchShape: Shape {
    var topRadius: CGFloat = 10
    var bottomRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let tr = min(topRadius, w / 2, h)
        let br = min(bottomRadius, (w - 2 * tr) / 2, h - tr)

        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        // top-left concave flare into the bar above
        p.addQuadCurve(to: CGPoint(x: tr, y: tr), control: CGPoint(x: tr, y: 0))
        p.addLine(to: CGPoint(x: tr, y: h - br))
        // bottom-left convex corner
        p.addQuadCurve(to: CGPoint(x: tr + br, y: h), control: CGPoint(x: tr, y: h))
        p.addLine(to: CGPoint(x: w - tr - br, y: h))
        // bottom-right convex corner
        p.addQuadCurve(to: CGPoint(x: w - tr, y: h - br), control: CGPoint(x: w - tr, y: h))
        p.addLine(to: CGPoint(x: w - tr, y: tr))
        // top-right concave flare
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - tr, y: 0))
        p.closeSubpath()
        return p
    }
}
