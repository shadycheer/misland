import SwiftUI
import AppKit

struct IslandRootView: View {
    @State var coordinator: PlaybackCoordinator
    /// Expand state + current-screen geometry. `hovering` is driven by the
    /// AppDelegate mouse monitor; `peeking` by track changes; `geo` follows the
    /// display the island is currently on.
    @State var islandState: IslandState
    /// Called when the history browser opens/closes so the AppDelegate can resize the
    /// window (and refresh hit rects) to fit the taller panel.
    var onBrowserResize: (Bool) -> Void = { _ in }
    /// Pops the settings menu (更多设置 / 退出) at the cursor — handled by the
    /// AppDelegate, which can show an NSMenu without the panel becoming key.
    var onSettingsMenu: () -> Void = {}

    @State private var peekTask: DispatchWorkItem?
    @State private var history = HistoryBrowserModel()
    @AppStorage("autoPeek") private var autoPeek = true

    private var geo: IslandGeometry { islandState.geo }
    private var expanded: Bool { islandState.expanded }

    /// Top strip aligned with the notch (its left/right shoulders hold the
    /// browse + settings icons). On notch-less screens it's a thin top bar.
    private var stripHeight: CGFloat {
        geo.hasNotch ? geo.notchHeight : IslandLayout.noNotchStripHeight
    }
    private var collapsedWidth: CGFloat {
        geo.hasNotch ? geo.notchWidth + 2 * IslandLayout.sideWidth : IslandLayout.collapsedWidth
    }
    private var collapsedHeight: CGFloat {
        geo.hasNotch ? geo.notchHeight : geo.barHeight
    }
    private var expandedContentHeight: CGFloat {
        islandState.browserOpen ? IslandLayout.browserHeight : IslandLayout.expandedHeight
    }
    private var expandedTotalHeight: CGFloat { stripHeight + expandedContentHeight }
    private var maxExpandedTotalHeight: CGFloat { stripHeight + IslandLayout.browserHeight }

    // Critically damped springs — smooth grow/shrink with NO overshoot/bounce.
    private let expandCurve = Animation.spring(response: 0.40, dampingFraction: 1.0)
    private let collapseCurve = Animation.spring(response: 0.30, dampingFraction: 1.0)
    private var sizeCurve: Animation { expanded ? expandCurve : collapseCurve }

    /// Show whenever there's a current track (playing OR paused) — pausing must
    /// not make it vanish. Hidden only when nothing is loaded (no player / no
    /// track), e.g. launching at login with nothing going on.
    private var visible: Bool { coordinator.track != nil || expanded }

    var body: some View {
        // Corner radii ANIMATE between states (NotchShape.animatableData rides the
        // existing size animation). Collapsed = (6, 14) — the real MacBook notch's
        // corner radius, so the pill blends with the hardware notch. Expanded =
        // (19, 24) — rounder so the tall panel doesn't read as square. These exact
        // pairs come from boring.notch, an overlay tuned to the physical notch.
        let tr: CGFloat = expanded ? 19 : 6
        let br: CGFloat = expanded ? 24 : 14
        let shape = NotchShape(topRadius: tr, bottomRadius: br)
        let w = expanded ? IslandLayout.expandedWidth : collapsedWidth
        let h = expanded ? expandedTotalHeight : collapsedHeight
        return ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                shape.fill(.black)
                Group {
                    if expanded {
                        expandedView
                            .transition(.identity)
                    } else {
                        collapsedView
                            .transition(.identity)
                    }
                }
                .transaction { tx in
                    tx.disablesAnimations = true
                }
            }
            .frame(width: w, height: h, alignment: .top)
            .clipShape(shape)
            .animation(sizeCurve, value: expanded)
            .animation(islandState.browserOpen ? expandCurve : collapseCurve, value: islandState.browserOpen)
        }
        .frame(width: IslandLayout.expandedWidth, height: maxExpandedTotalHeight, alignment: .top)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: visible)
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
                // No notch: a pill with art + song title (truncated) + bars.
                HStack(spacing: 8) {
                    artworkThumb
                    Text(coordinator.track?.title ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                    AudioBars(playing: coordinator.state?.isPlaying ?? false)
                }
                .padding(.horizontal, 12)
                .frame(width: collapsedWidth, height: collapsedHeight)
            }
        }
    }

    private var artworkThumb: some View {
        Group {
            if let img = coordinator.track?.artwork {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(0.18))
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - Expanded: full player below the notch

    private var expandedView: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: stripHeight)   // notch-height strip (icons overlaid)
            expandedContent
        }
        .frame(width: IslandLayout.expandedWidth, height: maxExpandedTotalHeight, alignment: .top)
        // Browse (left shoulder) + settings (right shoulder), flanking the notch
        // at its own height. Hidden while browsing (the browser has its own bar).
        .overlay(alignment: .top) {
            if !islandState.browserOpen { notchControls }
        }
    }

    private var expandedContent: some View {
        ZStack(alignment: .top) {
            if islandState.browserOpen {
                HistoryBrowserView(model: history, onClose: closeBrowser)
                    .transition(.identity)
            } else {
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
                .transition(.identity)
            }
        }
        .frame(width: IslandLayout.expandedWidth, height: IslandLayout.browserHeight, alignment: .top)
        .clipped()
        .transaction { tx in
            tx.animation = nil
        }
    }

    /// The two icons sitting in the notch strip, pushed to the left/right
    /// shoulders so they straddle the camera cutout.
    private var notchControls: some View {
        HStack(spacing: 0) {
            StripButton(system: "clock.arrow.circlepath", size: 15, action: openBrowser)
            Spacer(minLength: 0)
            StripButton(system: "gearshape", size: 15, action: onSettingsMenu)
        }
        .padding(.horizontal, IslandLayout.expandedHorizontalPadding)
        .frame(width: IslandLayout.expandedWidth, height: stripHeight)
    }

    /// Open recent playback history. Resizing the window happens via the
    /// AppDelegate callback.
    private func openBrowser() {
        history.open()
        islandState.browserOpen = true
        onBrowserResize(true)
    }

    private func closeBrowser() {
        islandState.browserOpen = false
        onBrowserResize(false)
    }
}

/// Small icon button for the notch strip — subtle by default, brightens on hover.
private struct StripButton: View {
    let system: String
    var size: CGFloat = 16
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white.opacity(hover ? 1 : 0.7))
                .frame(width: size + 14, height: size + 10)   // generous hit area
                .contentShape(Rectangle())
                .scaleEffect(hover ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hover = h }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
