import SwiftUI

struct IslandRootView: View {
    @State var coordinator: PlaybackCoordinator
    let canLike: Bool
    @State private var expanded = false

    var body: some View {
        Group {
            if expanded {
                ExpandedPlayer(
                    track: coordinator.track,
                    state: coordinator.state,
                    canLike: canLike,
                    onPlayPause: coordinator.playPause,
                    onNext: coordinator.next,
                    onPrev: coordinator.previous,
                    onSeek: coordinator.seek(to:),
                    onToggleLike: coordinator.toggleLike
                )
            } else {
                CollapsedPill(track: coordinator.track,
                              isPlaying: coordinator.state?.isPlaying ?? false)
                    .frame(width: IslandLayout.collapsedWidth)
            }
        }
        .clipShape(.rect(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        .onHover { hovering in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                expanded = hovering
            }
        }
    }
}
