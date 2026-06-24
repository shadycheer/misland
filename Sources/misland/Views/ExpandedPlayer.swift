import SwiftUI
import AppKit

struct ExpandedPlayer: View {
    let track: Track?
    let state: PlaybackState?
    let canLike: Bool
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrev: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onToggleLike: () -> Void
    let onExport: () -> Void
    let onOpen: (String?) -> Void

    @AppStorage("showExportButton") private var showExportButton = true
    @State private var copied = false
    @State private var scrubPosition: TimeInterval?
    @State private var scrubbing = false

    private let verticalPadding: CGFloat = 14
    private var contentWidth: CGFloat { IslandLayout.expandedContentWidth }
    private var contentHeight: CGFloat { IslandLayout.expandedHeight - 2 * verticalPadding }
    private var hasAlbum: Bool { !(track?.album ?? "").isEmpty && track?.album != track?.title }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                topRow
                Spacer(minLength: 12)
                progress
                Spacer(minLength: 14)
                transport
            }
            .frame(width: contentWidth, height: contentHeight, alignment: .top)
            .padding(.top, verticalPadding)
        }
        .frame(width: IslandLayout.expandedWidth, height: IslandLayout.expandedHeight, alignment: .top)
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 3) {
                LinkText(text: track?.title ?? "未在播放", link: track?.links?.track,
                         font: .system(size: 15, weight: .semibold),
                         color: .white, onOpen: onOpen)
                LinkText(text: track?.artist ?? "", link: track?.links?.artist,
                         font: .system(size: 12),
                         color: .white.opacity(0.64), onOpen: onOpen)
                if hasAlbum {
                    LinkText(text: track?.album ?? "", link: track?.links?.album,
                             font: .system(size: 11),
                             color: .white.opacity(0.42), onOpen: onOpen)
                }
            }
            .padding(.top, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            HStack(spacing: 12) {
                if showExportButton, track != nil {
                    ControlButton(system: copied ? "checkmark" : "square.and.arrow.up",
                                  size: 14, tint: copied ? .green : .white) {
                        onExport()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                }
                if canLike {
                    let liked = track?.isLiked ?? false
                    ControlButton(
                        system: liked ? "heart.fill" : "heart",
                        size: 16,
                        tint: liked ? .pink : .white,
                        action: onToggleLike
                    )
                }
            }
            .padding(.top, 4)
            .frame(minWidth: 74, alignment: .trailing)
        }
        .frame(height: 64)
    }

    @ViewBuilder private var artwork: some View {
        Group {
            if let img = track?.artwork {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.12))
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let livePosition = scrubPosition ?? estimatedPosition(at: context.date)
            let dur = max(track?.duration ?? 1, 1)
            let frac = min(max(livePosition / dur, 0), 1)
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22)).frame(height: 4)
                        Capsule().fill(.white.opacity(0.9))
                            .frame(width: max(0, geo.size.width * frac), height: 4)
                        Circle()
                            .fill(.white.opacity(scrubbing ? 1 : 0.88))
                            .frame(width: scrubbing ? 8 : 6, height: scrubbing ? 8 : 6)
                            .offset(x: max(0, min(geo.size.width - (scrubbing ? 8 : 6), geo.size.width * frac - (scrubbing ? 4 : 3))))
                            .opacity(track == nil ? 0 : 1)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                scrubbing = true
                                let f = min(max(v.location.x / geo.size.width, 0), 1)
                                scrubPosition = Double(f) * dur
                            }
                            .onEnded { v in
                                let f = min(max(v.location.x / geo.size.width, 0), 1)
                                let target = Double(f) * dur
                                scrubPosition = target
                                onSeek(target)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    scrubbing = false
                                    scrubPosition = nil
                                }
                            }
                    )
                }
                .frame(height: 14)
                HStack {
                    Text(fmt(livePosition))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 42, alignment: .leading)
                    Spacer()
                    Text(fmt(dur))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 42, alignment: .trailing)
                }
            }
        }
        .frame(height: 34)
    }

    private func estimatedPosition(at date: Date) -> TimeInterval {
        guard let state else { return 0 }
        let dur = max(track?.duration ?? 0, 0)
        var value = state.position
        if state.isPlaying {
            value += date.timeIntervalSince(state.sampledAt)
        }
        return dur > 0 ? min(max(value, 0), dur) : max(value, 0)
    }

    private var transport: some View {
        HStack(spacing: 36) {
            ControlButton(system: "backward.fill", size: 15, action: onPrev)
            ControlButton(system: (state?.isPlaying ?? false) ? "pause.fill" : "play.fill",
                          size: 20, action: onPlayPause)
            ControlButton(system: "forward.fill", size: 15, action: onNext)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
    }

    private func fmt(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// Text that opens a link on click (hover underline + pointer) when `link` is
/// present; otherwise plain text.
private struct LinkText: View {
    let text: String
    let link: String?
    let font: Font
    let color: Color
    let onOpen: (String?) -> Void
    @State private var hover = false

    var body: some View {
        if let link {
            Text(text)
                .font(font).foregroundStyle(color).lineLimit(1)
                .underline(hover)
                .contentShape(Rectangle())
                .onHover { h in
                    hover = h
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .onTapGesture { onOpen(link) }
        } else {
            Text(text).font(font).foregroundStyle(color).lineLimit(1)
        }
    }
}

/// A transport/like button with a hover highlight (brighten + slight scale).
private struct ControlButton: View {
    let system: String
    let size: CGFloat
    var tint: Color = .white
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size))
                .foregroundStyle(tint.opacity(hover ? 1 : 0.78))
                .frame(width: 30, height: 30)
                .scaleEffect(hover ? 1.15 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hover = h }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
