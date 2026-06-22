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

    // MARK: - Collapsed: info flanking the notch on the menu-bar row

    @ViewBuilder private var collapsedView: some View {
        if geo.hasNotch {
            HStack(spacing: 0) {
                leftWing
                Color.clear.frame(width: geo.notchWidth, height: geo.notchHeight)
                rightWing
            }
            .frame(height: geo.notchHeight)
        } else {
            CollapsedPill(track: coordinator.track,
                          isPlaying: coordinator.state?.isPlaying ?? false)
                .frame(width: IslandLayout.collapsedWidth)
                .clipShape(.rect(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        }
    }

    private var leftWing: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            artworkThumb.padding(.trailing, 7)
        }
        .frame(width: IslandLayout.sideWidth, height: geo.notchHeight)
        .background(.black)
        .clipShape(.rect(bottomLeadingRadius: 14))
    }

    private var rightWing: some View {
        HStack(spacing: 0) {
            AudioBars(playing: coordinator.state?.isPlaying ?? false).padding(.leading, 9)
            Spacer(minLength: 0)
        }
        .frame(width: IslandLayout.sideWidth, height: geo.notchHeight)
        .background(.black)
        .clipShape(.rect(bottomTrailingRadius: 14))
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
