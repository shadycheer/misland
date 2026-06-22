import SwiftUI

struct IslandRootView: View {
    @State var coordinator: PlaybackCoordinator
    let geo: IslandGeometry
    /// Called when hover state flips so the window can update its hit region.
    let onExpandChange: (Bool) -> Void
    @State private var expanded = false

    private var notchInset: CGFloat { geo.hasNotch ? geo.notchHeight : 0 }

    private var collapsedWidth: CGFloat {
        geo.hasNotch ? geo.notchWidth + 2 * IslandLayout.sideWidth : IslandLayout.collapsedWidth
    }
    private var collapsedHeight: CGFloat {
        geo.hasNotch ? geo.notchHeight : IslandLayout.collapsedHeight
    }
    private var expandedTotalHeight: CGFloat { notchInset + IslandLayout.expandedHeight }

    var body: some View {
        ZStack(alignment: .top) {
            collapsedView.opacity(expanded ? 0 : 1)
            expandedView.opacity(expanded ? 1 : 0)
        }
        // One black shape whose size springs between the two states; content
        // cross-fades on top, so it reads as the island growing, not swapping.
        .frame(width: expanded ? IslandLayout.expandedWidth : collapsedWidth,
               height: expanded ? expandedTotalHeight : collapsedHeight,
               alignment: .top)
        .background(.black)
        .clipShape(.rect(bottomLeadingRadius: expanded ? 22 : 14,
                         bottomTrailingRadius: expanded ? 22 : 14))
        .onHover { hovering in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                expanded = hovering
            }
            onExpandChange(hovering)
        }
    }

    // MARK: - Collapsed: art left, bars right, single bar across the notch

    private var collapsedView: some View {
        HStack(spacing: 0) {
            artworkThumb
            Spacer(minLength: 0)
            AudioBars(playing: coordinator.state?.isPlaying ?? false)
        }
        .padding(.horizontal, 11)
        .frame(width: collapsedWidth, height: collapsedHeight)
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

    // MARK: - Expanded: full player below the notch

    private var expandedView: some View {
        VStack(spacing: 0) {
            if notchInset > 0 { Color.clear.frame(height: notchInset) }
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
        .frame(width: IslandLayout.expandedWidth, height: expandedTotalHeight, alignment: .top)
    }
}
