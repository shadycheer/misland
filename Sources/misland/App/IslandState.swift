import Observation

/// Shared expand state. The AppDelegate's global mouse monitor drives `hovering`
/// against the island's exact screen rect (reliable, unlike SwiftUI .onHover);
/// the view drives `peeking` on track changes. The island is expanded if either.
@Observable
final class IslandState {
    var hovering = false
    var peeking = false
    /// Geometry of the screen the island currently lives on — updated as the
    /// island follows the cursor across displays (notch vs floating).
    var geo = IslandGeometry(hasNotch: false, notchWidth: 0, notchHeight: 0)
    var expanded: Bool { hovering || peeking }
}
