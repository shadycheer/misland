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

    // Cubic-bezier (cubic-bezier-style) timing curves — tweak the 4 control
    // numbers + duration to retune the feel. Expand pops out with a slight
    // overshoot; collapse snaps back quicker with no bounce.
    private let expandCurve = Animation.timingCurve(0.2, 1.25, 0.3, 1.0, duration: 0.42)
    private let collapseCurve = Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.26)
    private var sizeCurve: Animation { expanded ? expandCurve : collapseCurve }

    var body: some View {
        ZStack(alignment: .top) {
            collapsedView
                .opacity(expanded ? 0 : 1)
                .animation(.easeOut(duration: 0.14), value: expanded)
            expandedView
                .opacity(expanded ? 1 : 0)
                .animation(.easeOut(duration: 0.20), value: expanded)
        }
        // One black shape; only its size animates (on the timing curve), so it
        // reads as the island physically popping out / snapping back.
        .frame(width: expanded ? IslandLayout.expandedWidth : collapsedWidth,
               height: expanded ? expandedTotalHeight : collapsedHeight,
               alignment: .top)
        .animation(sizeCurve, value: expanded)
        .background(.black)
        .clipShape(.rect(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
        .onHover { hovering in
            expanded = hovering
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
