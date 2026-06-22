import SwiftUI

struct ExpandedPlayer: View {
    let track: Track?
    let state: PlaybackState?
    let canLike: Bool
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrev: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onToggleLike: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(track?.title ?? "未在播放")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(track?.artist ?? "")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    Text(track?.album ?? "")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 4)
                if canLike {
                    Button(action: onToggleLike) {
                        Image(systemName: (track?.isLiked ?? false) ? "heart.fill" : "heart")
                            .font(.system(size: 15))
                            .foregroundStyle((track?.isLiked ?? false) ? .pink : .white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 64)

            progress
            transport
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: IslandLayout.expandedWidth, height: IslandLayout.expandedHeight, alignment: .top)
    }

    @ViewBuilder private var artwork: some View {
        Group {
            if let img = track?.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.12)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
            Button(action: onPrev) {
                Image(systemName: "backward.fill").font(.system(size: 15))
            }.buttonStyle(.plain)
            Button(action: onPlayPause) {
                Image(systemName: (state?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
            }.buttonStyle(.plain)
            Button(action: onNext) {
                Image(systemName: "forward.fill").font(.system(size: 15))
            }.buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }

    private func fmt(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
