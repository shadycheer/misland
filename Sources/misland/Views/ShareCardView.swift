import AppKit
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
        switch source {
        case .neteaseMusic:
            NeteaseShareCard(track: track, qr: qr)
        case .qqMusic:
            QQMusicShareCard(track: track, qr: qr)
        default:
            spotifyStyle
        }
    }

    private var spotifyStyle: some View {
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

private struct NeteaseShareCard: View {
    let track: Track
    let qr: NSImage?

    private let width: CGFloat = 320
    private let paddingX: CGFloat = 16
    private let paddingTop: CGFloat = 16
    private let paddingBottom: CGFloat = 20
    private let gap: CGFloat = 20
    private var stage: CGFloat { width * 0.84 }
    private var disc: CGFloat { stage * (1 - 0.07 * 2) }
    private var label: CGFloat { disc * 0.62 }
    private var palette: (primary: Color, secondary: Color) {
        track.artwork?.musicardPalette() ?? (
            Color(red: 0.23, green: 0.23, blue: 0.23),
            Color(red: 0.10, green: 0.10, blue: 0.10)
        )
    }

    var body: some View {
        VStack(spacing: gap) {
            vinyl
            VStack(spacing: 6) {
                Text(track.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                Text(track.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            foot
        }
        .padding(.top, paddingTop)
        .padding(.horizontal, paddingX)
        .padding(.bottom, paddingBottom)
        .frame(width: width)
        .background {
            LinearGradient(
                colors: [
                    palette.primary.musicardDarkened(0.55),
                    palette.secondary.musicardDarkened(0.75),
                    Color(red: 0.04, green: 0.04, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, Color(red: 0.93, green: 0.25, blue: 0.25), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 2)
                Spacer()
            }
        }
    }

    private var vinyl: some View {
        ZStack {
            Circle().fill(.white.opacity(0.07))
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.12), Color(white: 0.03)],
                                     center: .center, startRadius: 0, endRadius: disc / 2))
                .frame(width: disc, height: disc)
                .shadow(color: .black.opacity(0.55), radius: 12, y: 8)
                .overlay(grooves)
                .overlay(shine.clipShape(Circle()))
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
            Circle()
                .fill(.white.opacity(0.55))
                .frame(width: label + 2, height: label + 2)
            cover
                .frame(width: label, height: label)
                .clipShape(Circle())
        }
        .frame(width: stage, height: stage)
    }

    private var grooves: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { i in
                Circle()
                    .stroke(.white.opacity(i.isMultiple(of: 2) ? 0.07 : 0.04), lineWidth: 0.5)
                    .frame(width: label + CGFloat(i) * 6, height: label + CGFloat(i) * 6)
            }
        }
    }

    private var shine: some View {
        LinearGradient(colors: [.clear, .white.opacity(0.14), .clear],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .rotationEffect(.degrees(25))
            .frame(width: disc, height: disc)
    }

    private var cover: some View {
        Group {
            if let img = track.artwork {
                Image(nsImage: img).resizable().interpolation(.high).scaledToFill()
            } else {
                Color(white: 0.1)
            }
        }
    }

    private var foot: some View {
        HStack {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color(red: 0.93, green: 0.25, blue: 0.25))
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)
                Text("网易云音乐")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            Spacer()
            QRView(qr: qr, size: 44, pad: 3, radius: 4)
        }
        .frame(height: 44)
    }
}

private struct QQMusicShareCard: View {
    let track: Track
    let qr: NSImage?

    private let width: CGFloat = 320
    private let padding: CGFloat = 22
    private var content: CGFloat { width - padding * 2 }
    private var sleeve: CGFloat { content * 0.78 }
    private var disc: CGFloat { content * 0.74 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            stage
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 0.10, green: 0.15, blue: 0.06))
                    .lineLimit(2)
                Text(track.artist)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color(red: 0.10, green: 0.15, blue: 0.06).opacity(0.62))
                    .lineLimit(1)
            }
            foot
        }
        .padding(padding)
        .frame(width: width)
        .background(Color(red: 0.78, green: 0.86, blue: 0.63))
    }

    private var stage: some View {
        ZStack(alignment: .leading) {
            HStack {
                Spacer()
                discView
                    .frame(width: disc, height: disc)
                    .offset(x: 0)
            }
            sleeveView
                .frame(width: sleeve, height: sleeve)
        }
        .frame(width: content, height: sleeve)
    }

    private var discView: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.37, green: 0.39, blue: 0.36),
                                              Color(red: 0.24, green: 0.25, blue: 0.23)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Color(red: 0.11, green: 0.16, blue: 0.05).opacity(0.28), radius: 7, y: 4)
            ForEach(0..<28, id: \.self) { i in
                Circle()
                    .stroke(.white.opacity(0.05), lineWidth: 0.5)
                    .frame(width: 8 + CGFloat(i) * 4, height: 8 + CGFloat(i) * 4)
            }
            Circle()
                .fill(Color(red: 0.78, green: 0.86, blue: 0.63))
                .frame(width: disc * 0.16, height: disc * 0.16)
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
    }

    private var sleeveView: some View {
        ZStack {
            Color.white
            Group {
                if let img = track.artwork {
                    Image(nsImage: img).resizable().interpolation(.high).scaledToFill()
                } else {
                    Color.white.opacity(0.6)
                }
            }
            .padding(4)
            .clipped()
        }
        .shadow(color: Color(red: 0.11, green: 0.16, blue: 0.05).opacity(0.26), radius: 11, y: 8)
    }

    private var foot: some View {
        HStack {
            QqGlyph()
                .frame(width: 40, height: 40)
            Spacer()
            QRView(qr: qr, size: 48, pad: 3, radius: 0)
        }
        .frame(height: 48)
    }
}

private struct QqGlyph: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.99, green: 0.80, blue: 0.09))
            Image(systemName: "music.note")
                .font(.system(size: 21, weight: .black))
                .foregroundStyle(Color(red: 0.05, green: 0.69, blue: 0.32))
                .rotationEffect(.degrees(-12))
        }
    }
}

private struct QRView: View {
    let qr: NSImage?
    let size: CGFloat
    let pad: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let qr {
                Image(nsImage: qr).resizable().interpolation(.none)
                    .padding(pad)
                    .background(Color.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

private extension NSImage {
    func musicardPalette() -> (primary: Color, secondary: Color)? {
        guard let tiff = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        let stepX = max(1, width / 24)
        let stepY = max(1, height / 24)
        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var total: CGFloat = 0

        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let r = color.redComponent
                let g = color.greenComponent
                let b = color.blueComponent
                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
                let brightness = maxC
                let weight = max(0.15, saturation) * max(0.2, brightness)
                totalR += r * weight
                totalG += g * weight
                totalB += b * weight
                total += weight
            }
        }

        guard total > 0 else { return nil }
        let primary = Color(red: totalR / total, green: totalG / total, blue: totalB / total)
        let darker = Color(red: max(0, totalR / total * 0.72),
                           green: max(0, totalG / total * 0.72),
                           blue: max(0, totalB / total * 0.72))
        return (primary, darker)
    }
}

private extension Color {
    func musicardDarkened(_ amount: CGFloat) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return Color(
            red: max(0, ns.redComponent * (1 - amount)),
            green: max(0, ns.greenComponent * (1 - amount)),
            blue: max(0, ns.blueComponent * (1 - amount))
        )
    }
}
