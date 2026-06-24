import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

enum CardExporter {
    /// Render the share card for the current track and both copy it to the
    /// clipboard and offer to save it as a PNG.
    @MainActor
    static func export(track: Track?, source: SourceKind?) {
        guard let track else { return }
        let exportTrack = trackWithBestArtwork(track, source: source)
        let qr = qrImage(shareURL(track: exportTrack, source: source))
        let scale: CGFloat = 6   // 320pt design -> 1920px PNG, matching the web export
        let renderer = ImageRenderer(content: ShareCardView(track: exportTrack, source: source, qr: qr))
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return }

        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let image = NSImage(cgImage: cg,
                            size: NSSize(width: cg.width, height: cg.height))

        // Copy to clipboard — paste straight into chat apps. Both the image and
        // its PNG data, so apps that prefer file data also get it.
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        pb.setData(png, forType: .png)
    }

    private static func trackWithBestArtwork(_ track: Track, source: SourceKind?) -> Track {
        guard let image = bestArtwork(for: track, source: source), image !== track.artwork else {
            return track
        }
        var copy = track
        copy.artwork = image
        return copy
    }

    private static func bestArtwork(for track: Track, source: SourceKind?) -> NSImage? {
        switch source {
        case .qqMusic:
            guard let metadata = QQMusicArchiveMetadataStore.shared.metadata(title: track.title, artist: track.artist),
                  let url = metadata.artworkFileURL,
                  let image = NSImage(contentsOf: url) else {
                return track.artwork
            }
            return larger(image, than: track.artwork) ? image : track.artwork
        case .neteaseMusic:
            guard let metadata = NetEaseMusicLibraryStore.shared.metadata(title: track.title, artist: track.artist, album: track.album),
                  let urlString = metadata.artworkURL else {
                return track.artwork
            }
            if let cached = ArtworkCache.shared.cached("netease-url:\(urlString)") ?? ArtworkCache.shared.cached(urlString) {
                return larger(cached, than: track.artwork) ? cached : track.artwork
            }
            guard let url = URL(string: urlString),
                  let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data) else {
                return track.artwork
            }
            return larger(image, than: track.artwork) ? image : track.artwork
        default:
            return track.artwork
        }
    }

    private static func larger(_ lhs: NSImage, than rhs: NSImage?) -> Bool {
        guard let rhs else { return true }
        return pixelArea(lhs) > pixelArea(rhs)
    }

    private static func pixelArea(_ image: NSImage) -> Int {
        if let rep = image.representations.max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }) {
            return rep.pixelsWide * rep.pixelsHigh
        }
        return Int(image.size.width * image.size.height)
    }

    /// A public URL to the track, for the QR code. Spotify only — Apple Music
    /// exposes no stable public URL from the local app.
    private static func shareURL(track: Track, source: SourceKind?) -> URL? {
        if let link = track.links?.track, let url = URL(string: link) {
            return url
        }
        guard source == .spotify else { return nil }
        let prefix = "spotify:track:"
        guard track.id.hasPrefix(prefix) else { return nil }
        let id = String(track.id.dropFirst(prefix.count))
        return URL(string: "https://open.spotify.com/track/\(id)")
    }

    private static func qrImage(_ url: URL?) -> NSImage? {
        guard let url, let data = url.absoluteString.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
