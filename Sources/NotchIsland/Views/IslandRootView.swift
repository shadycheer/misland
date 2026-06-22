import SwiftUI

struct IslandRootView: View {
    @State var coordinator: PlaybackCoordinator
    let geo: IslandGeometry
    /// Called when hover state flips so the window can resize to match.
    let onExpandChange: (Bool) -> Void
    @State private var expanded = false

    var body: some View {
        content
            .onHover { hovering in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                    expanded = hovering
                }
                onExpandChange(hovering)
            }
    }

    @ViewBuilder private var content: some View {
        if expanded { expandedView } else { collapsedView }
    }

    // MARK: - Collapsed: one cohesive bar spanning the notch

    private var collapsedWidth: CGFloat {
        geo.hasNotch ? geo.notchWidth + 2 * IslandLayout.sideWidth : IslandLayout.collapsedWidth
    }
    private var collapsedHeight: CGFloat {
        geo.hasNotch ? geo.notchHeight : IslandLayout.collapsedHeight
    }

    private var collapsedView: some View {
        // One black bar: art on the left, bars on the right, the notch (or empty
        // gap) bridged by continuous black between them.
        HStack(spacing: 0) {
            artworkThumb
            Spacer(minLength: 0)
            AudioBars(playing: coordinator.state?.isPlaying ?? false)
        }
        .padding(.horizontal, 11)
        .frame(width: collapsedWidth, height: collapsedHeight)
        .background(.black)
        .clipShape(.rect(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
    }

    private var artworkThumb: some View {
        Group {
            if let img = coordinator.track?.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.18)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Expanded: full player dropping below the notch

    @ViewBuilder private var expandedView: some View {
        if geo.hasNotch {
            VStack(spacing: 0) {
                Color.black.frame(width: IslandLayout.expandedWidth, height: geo.notchHeight)
                player
            }
            .clipShape(.rect(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
        } else {
            player.clipShape(.rect(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
        }
    }

    private var player: some View {
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
    }
}
