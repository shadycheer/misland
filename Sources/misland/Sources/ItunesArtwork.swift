import AppKit

/// Fallback cover lookup via the public iTunes Search API (no key). Used when
/// Apple Music doesn't expose a track's artwork bytes locally (common for
/// streaming/catalog tracks the app renders from its own cache). Call off-main.
enum ItunesArtwork {
    static func fetch(artist: String, title: String) -> NSImage? {
        guard var comps = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = comps.url,
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]],
              let art100 = results.first?["artworkUrl100"] as? String else { return nil }
        // Upscale 100x100 → 600x600 for a crisp cover.
        let big = art100.replacingOccurrences(of: "100x100", with: "600x600")
        guard let imgURL = URL(string: big),
              let imgData = try? Data(contentsOf: imgURL) else { return nil }
        return NSImage(data: imgData)
    }
}
