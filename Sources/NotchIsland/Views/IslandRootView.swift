import SwiftUI

struct IslandRootView: View {
    @State var coordinator: PlaybackCoordinator
    /// Height of the notch (0 on notch-less displays). The black strip of this
    /// height sits behind the notch so the panel fuses with it.
    let topInset: CGFloat
    /// Width of the collapsed pill — matches the notch width when there is one.
    let collapsedWidth: CGFloat
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            if topInset > 0 {
                Color.black.frame(height: topInset)
            }
            if expanded {
                ExpandedPlayer(
                    track: coordinator.track,
                    state: coordinator.state,
                    canLike: coordinator.canLike,
                    onPlayPause: coordinator.playPause,
                    onNext: coordinator.next,
                    onPrev: coordinator.previous,
                    onSeek: coordinator.seek(to:),
                    onToggleLike: coordinator.toggleLike
                )
            } else {
                CollapsedPill(track: coordinator.track,
                              isPlaying: coordinator.state?.isPlaying ?? false)
                    .frame(width: collapsedWidth)
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
