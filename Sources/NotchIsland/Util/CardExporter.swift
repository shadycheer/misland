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
        let qr = qrImage(shareURL(track: track, source: source))
        let scale: CGFloat = 6   // 320pt design -> 1920px PNG, matching the web export
        let renderer = ImageRenderer(content: ShareCardView(track: track, source: source, qr: qr))
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return }

        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let image = NSImage(cgImage: cg,
                            size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))

        // Copy to clipboard — paste straight into chat apps. Both the image and
        // its PNG data, so apps that prefer file data also get it.
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        pb.setData(png, forType: .png)
    }

    /// A public URL to the track, for the QR code. Spotify only — Apple Music
    /// exposes no stable public URL from the local app.
    private static func shareURL(track: Track, source: SourceKind?) -> URL? {
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
