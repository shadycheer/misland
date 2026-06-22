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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(track?.title ?? "Not playing")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(track?.artist ?? "")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    Text(track?.album ?? "")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                }
                Spacer()
                if canLike {
                    Button(action: onToggleLike) {
                        Image(systemName: (track?.isLiked ?? false) ? "heart.fill" : "heart")
                            .foregroundStyle((track?.isLiked ?? false) ? .pink : .white)
                    }.buttonStyle(.plain)
                }
            }
            progress
            transport
        }
        .padding(16)
        .frame(width: 430, height: 200)
        .background(.black)
    }

    @ViewBuilder private var artwork: some View {
        if let img = track?.artwork {
            Image(nsImage: img).resizable().frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12).fill(.gray).frame(width: 74, height: 74)
        }
    }

    private var progress: some View {
        let pos = state?.position ?? 0
        let dur = max(track?.duration ?? 1, 1)
        return VStack(spacing: 4) {
            Slider(value: Binding(
                get: { min(pos / dur, 1) },
                set: { onSeek($0 * dur) }
            )).tint(.white)
            HStack {
                Text(fmt(pos)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(fmt(dur)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 28) {
            Spacer()
            Button(action: onPrev) { Image(systemName: "backward.fill") }.buttonStyle(.plain)
            Button(action: onPlayPause) {
                Image(systemName: (state?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
            }.buttonStyle(.plain)
            Button(action: onNext) { Image(systemName: "forward.fill") }.buttonStyle(.plain)
            Spacer()
        }.foregroundStyle(.white)
    }

    private func fmt(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
