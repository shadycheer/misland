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

    private var hasAlbum: Bool { !(track?.album ?? "").isEmpty && track?.album != track?.title }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    LinkText(text: track?.title ?? "未在播放", link: track?.links?.track,
                             font: .system(size: 15, weight: .semibold),
                             color: .white, onOpen: onOpen)
                    LinkText(text: track?.artist ?? "", link: track?.links?.artist,
                             font: .system(size: 12),
                             color: .white.opacity(0.65), onOpen: onOpen)
                    if hasAlbum {
                        LinkText(text: track?.album ?? "", link: track?.links?.album,
                                 font: .system(size: 11),
                                 color: .white.opacity(0.4), onOpen: onOpen)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 14) {
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
                            size: 15,
                            tint: liked ? .pink : .white,
                            action: onToggleLike
                        )
                    }
                }
            }
            .frame(height: 68)

            Spacer(minLength: 10)
            progress
            Spacer(minLength: 12)
            transport
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: IslandLayout.expandedWidth, height: IslandLayout.expandedHeight, alignment: .top)
    }

    @ViewBuilder private var artwork: some View {
        Group {
            if let img = track?.artwork {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.12))
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .frame(width: 68, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var progress: some View {
        let pos = state?.position ?? 0
        let dur = max(track?.duration ?? 1, 1)
        let frac = min(max(pos / dur, 0), 1)
        return VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                    Capsule().fill(.white.opacity(0.9))
                        .frame(width: max(0, geo.size.width * frac), height: 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                    let f = min(max(v.location.x / geo.size.width, 0), 1)
                    onSeek(Double(f) * dur)
                })
            }
            .frame(height: 12)
            HStack {
                Text(fmt(pos)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(fmt(dur)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 36) {
            ControlButton(system: "backward.fill", size: 15, action: onPrev)
            ControlButton(system: (state?.isPlaying ?? false) ? "pause.fill" : "play.fill",
                          size: 20, action: onPlayPause)
            ControlButton(system: "forward.fill", size: 15, action: onNext)
        }
        .frame(maxWidth: .infinity)
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
                .scaleEffect(hover ? 1.15 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hover = h }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
