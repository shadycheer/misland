import SwiftUI
import AppKit

struct IslandRootView: View {
    @State var coordinator: PlaybackCoordinator
    let geo: IslandGeometry
    /// Expand state — `hovering` is driven by the AppDelegate's mouse monitor
    /// against the island's exact screen rect; `peeking` by track changes.
    @State var islandState: IslandState

    @State private var peekTask: DispatchWorkItem?
    @AppStorage("autoPeek") private var autoPeek = true

    private var expanded: Bool { islandState.expanded }

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

    var body: some View {
        let shape = NotchShape(topRadius: 6, bottomRadius: 14)
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
            .animation(sizeCurve, value: expanded)
            .frame(width: IslandLayout.expandedWidth, height: expandedTotalHeight, alignment: .top)
            .onChange(of: coordinator.track?.id) { _, newID in
                if newID != nil { peek() }
            }
    }

    /// Auto-peek: expand briefly on a track change, then collapse after 2s
    /// (unless the pointer is on it).
    private func peek() {
        guard autoPeek else { return }
        peekTask?.cancel()
        islandState.peeking = true
        let task = DispatchWorkItem { islandState.peeking = false }
        peekTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: task)
    }

    // MARK: - Collapsed: art left, bars right, single bar across the notch

    private var collapsedView: some View {
        Group {
            if geo.hasNotch {
                // Art hugs the camera's left, bars hug its right; the outer
                // shoulders are empty black framing them (not edge-jammed).
                HStack(spacing: 0) {
                    artworkThumb
                        .padding(.trailing, 8)
                        .frame(width: IslandLayout.sideWidth, alignment: .trailing)
                    Color.clear.frame(width: geo.notchWidth)
                    AudioBars(playing: coordinator.state?.isPlaying ?? false)
                        .padding(.leading, 9)
                        .frame(width: IslandLayout.sideWidth, alignment: .leading)
                }
                .frame(width: collapsedWidth, height: collapsedHeight)
            } else {
                // No notch: compact pill, art + bars together (no empty gap).
                HStack(spacing: 9) {
                    artworkThumb
                    AudioBars(playing: coordinator.state?.isPlaying ?? false)
                }
                .padding(.horizontal, 10)
                .frame(width: collapsedWidth, height: collapsedHeight)
            }
        }
    }

    private var artworkThumb: some View {
        Group {
            if let img = coordinator.track?.artwork {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.18)
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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
                onToggleLike: coordinator.toggleLike,
                onExport: { [coordinator] in
                    Task { @MainActor in
                        CardExporter.export(track: coordinator.track, source: coordinator.state?.source)
                    }
                },
                onOpen: { link in
                    if let link, let url = URL(string: link) { NSWorkspace.shared.open(url) }
                }
            )
        }
        .frame(width: IslandLayout.expandedWidth, height: expandedTotalHeight, alignment: .top)
    }
}
