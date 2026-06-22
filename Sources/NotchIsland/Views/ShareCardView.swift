import SwiftUI

/// The shareable "now playing" card, rendered to PNG by CardExporter. Inherits
/// the spotify-card web template: big cover, title/artist/album, a background
/// tinted by the cover's dominant colour, a platform badge, and a QR code.
struct ShareCardView: View {
    let track: Track
    let source: SourceKind?
    let qr: NSImage?

    private var accent: Color {
        switch source {
        case .spotify: return Color(red: 0.118, green: 0.843, blue: 0.376) // Spotify green
        case .appleMusic: return Color(red: 0.98, green: 0.23, blue: 0.43)  // Apple Music pink
        case .none: return .white
        }
    }
    private var platformName: String {
        switch source {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .none: return "Now Playing"
        }
    }
    private var tint: Color { Color(ArtworkColor.dominant(track.artwork)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            cover
            VStack(alignment: .leading, spacing: 6) {
                Text(track.title).font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white).lineLimit(2)
                Text(track.artist).font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                if !track.album.isEmpty {
                    Text(track.album).font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                    Text(platformName).font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(accent)
                Spacer()
                if let qr {
                    Image(nsImage: qr).resizable().interpolation(.none)
                        .frame(width: 60, height: 60)
                        .padding(5).background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(26)
        .frame(width: 360, height: 520, alignment: .top)
        .background(
            LinearGradient(colors: [tint, tint.opacity(0.45), .black],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    @ViewBuilder private var cover: some View {
        Group {
            if let img = track.artwork {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.12)
            }
        }
        .frame(width: 308, height: 308)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
