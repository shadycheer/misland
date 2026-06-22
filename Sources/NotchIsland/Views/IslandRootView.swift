import SwiftUI

struct IslandRootView: View {
    @State var coordinator: PlaybackCoordinator
    let geo: IslandGeometry
    /// Called when the visible (expanded) state flips so the window can update
    /// its mouse-interactive region.
    let onExpandChange: (Bool) -> Void

    @State private var hovering = false
    @State private var peeking = false
    @State private var peekTask: DispatchWorkItem?

    /// Expanded when the pointer is over it OR during an auto-peek.
    private var expanded: Bool { hovering || peeking }

    private var notchInset: CGFloat { geo.hasNotch ? geo.notchHeight : 0 }
    private var collapsedWidth: CGFloat {
        geo.hasNotch ? geo.notchWidth + 2 * IslandLayout.sideWidth : IslandLayout.collapsedWidth
    }
    private var collapsedHeight: CGFloat {
        geo.hasNotch ? geo.notchHeight : IslandLayout.collapsedHeight
    }
    private var expandedTotalHeight: CGFloat { notchInset + IslandLayout.expandedHeight }

    // Cubic-bezier timing — expand pops with a slight overshoot, collapse snaps back.
    private let expandCurve = Animation.timingCurve(0.2, 1.25, 0.3, 1.0, duration: 0.42)
    private let collapseCurve = Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.26)
    private var sizeCurve: Animation { expanded ? expandCurve : collapseCurve }

    // Top corners square so the island fuses with the notch / screen top; only
    // the bottom corners are rounded.
    private var radii: RectangleCornerRadii {
        .init(topLeading: 0, bottomLeading: 20, bottomTrailing: 20, topTrailing: 0)
    }

    var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
        shape
            .fill(.black)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    collapsedView
                        .opacity(expanded ? 0 : 1)
                        .animation(.easeOut(duration: 0.12), value: expanded)
                    expandedView
                        .opacity(expanded ? 1 : 0)
                        .scaleEffect(expanded ? 1 : 0.92, anchor: .top)
                        .animation(.easeOut(duration: 0.18), value: expanded)
                }
            }
            .frame(width: expanded ? IslandLayout.expandedWidth : collapsedWidth,
                   height: expanded ? expandedTotalHeight : collapsedHeight,
                   alignment: .top)
            .clipShape(shape)
            .frame(width: IslandLayout.expandedWidth, height: expandedTotalHeight, alignment: .top)
            .animation(sizeCurve, value: expanded)
            .onHover { h in
                hovering = h
                syncWindow()
            }
            .onChange(of: coordinator.track?.id) { _, newID in
                if newID != nil { peek() }
            }
    }

    private func syncWindow() { onExpandChange(expanded) }

    /// Auto-peek: expand briefly on a track change, then collapse after 2s
    /// (unless the pointer is on it).
    private func peek() {
        peekTask?.cancel()
        peeking = true
        syncWindow()
        let task = DispatchWorkItem {
            peeking = false
            syncWindow()
        }
        peekTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: task)
    }

    // MARK: - Collapsed: art left, bars right, single bar across the notch

    private var collapsedView: some View {
        HStack(spacing: 0) {
            artworkThumb
            Spacer(minLength: 0)
            AudioBars(playing: coordinator.state?.isPlaying ?? false)
        }
        .padding(.horizontal, 10)
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
