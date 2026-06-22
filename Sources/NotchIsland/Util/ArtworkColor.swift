import AppKit

enum ArtworkColor {
    static func dominant(_ image: NSImage?) -> NSColor {
        guard let image,
              let tiff = image.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff) else { return .black }
        let w = bmp.pixelsWide, h = bmp.pixelsHigh
        guard w > 0, h > 0 else { return .black }
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        let stepX = max(1, w / 16), stepY = max(1, h / 16)
        for x in stride(from: 0, to: w, by: stepX) {
            for y in stride(from: 0, to: h, by: stepY) {
                if let c = bmp.colorAt(x: x, y: y) {
                    r += c.redComponent; g += c.greenComponent; b += c.blueComponent; n += 1
                }
            }
        }
        guard n > 0 else { return .black }
        return NSColor(red: r/n, green: g/n, blue: b/n, alpha: 1)
    }
}
