import Observation

/// Shared expand state. The AppDelegate's global mouse monitor drives `hovering`
/// against the island's exact screen rect (reliable, unlike SwiftUI .onHover);
/// the view drives `peeking` on track changes. The island is expanded if either.
@Observable
final class IslandState {
    var hovering = false
    var peeking = false
    var expanded: Bool { hovering || peeking }
}
