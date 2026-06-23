import SwiftUI

/// Faithful port of spotify-card's canvas template (src/lib/card/spotify.ts):
/// 320pt design width, flat black, 280 square cover, 800 title, dim artist,
/// foot = brand lockup (left) + QR (right). Rendered to PNG by CardExporter.
struct ShareCardView: View {
    let track: Track
    let source: SourceKind?
    let qr: NSImage?

    private let designW: CGFloat = 320
    private let pad: CGFloat = 20
    private var coverW: CGFloat { designW - pad * 2 } // 280

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            Spacer().frame(height: 16)
            Text(track.title)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 4)
            Text(track.artist)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 0.70, green: 0.70, blue: 0.70)) // #B3B3B3
                .lineLimit(1)
            Spacer().frame(height: 16)
            foot
        }
        .frame(width: coverW, alignment: .leading)
        .padding(pad)
        .background(Color.black)
    }

    private var cover: some View {
        // Overlay+clipped fills reliably in ImageRenderer; bare
        // .aspectRatio(.fill) can leave the image unscaled (white band).
        Color(red: 0.094, green: 0.094, blue: 0.094) // #181818
            .frame(width: coverW, height: coverW)
            .overlay {
                if let img = track.artwork {
                    Image(nsImage: img).resizable().interpolation(.high).scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var foot: some View {
        HStack(alignment: .center, spacing: 0) {
            brand
            Spacer(minLength: 8)
            if let qr {
                Image(nsImage: qr).resizable().interpolation(.none)
                    .frame(width: 38, height: 38)
                    .padding(3)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder private var brand: some View {
        if let lockup = BrandLockup.image(for: source) {
            Image(nsImage: lockup).resizable().interpolation(.high)
                .scaledToFit().frame(height: 24)
        } else {
            Text(source == .appleMusic ? "Apple Music" : "Now Playing")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
