import AppKit

/// Wrapper around Spotify desktop's bundled `spotify_cli` (Contents/MacOS/spotify_cli),
/// which talks to the running, logged-in desktop app's local desktop_api. Lets us
/// read/toggle "Liked Songs" locally — no OAuth, no Web API quota.
enum SpotifyCLI {
    /// Resolve the CLI inside whatever Spotify.app is installed; nil if absent.
    static var path: String? {
        guard let appURL = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.spotify.client") else { return nil }
        let cli = appURL.appendingPathComponent("Contents/MacOS/spotify_cli").path
        return FileManager.default.isExecutableFile(atPath: cli) ? cli : nil
    }

    static var isAvailable: Bool { path != nil }

    /// Run a command and return stdout. Synchronous — call off the main thread.
    @discardableResult
    private static func run(_ args: [String]) -> Data? {
        guard let path else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return data
    }

    /// Whether a track URI is in the user's Liked Songs. nil if unknown.
    static func isLiked(_ uri: String) -> Bool? {
        guard let data = run(["library", "contains", uri, "--format", "json"]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contains = obj["contains"] as? [String: Any],
              let liked = contains[uri] as? Bool else { return nil }
        return liked
    }

    /// Add/remove a track URI to/from Liked Songs.
    static func setLiked(_ uri: String, _ liked: Bool) {
        run(["library", liked ? "add" : "remove", uri])
    }

    /// Liked-status for many URIs in ONE call → uri:isLiked map.
    static func contains(_ uris: [String]) -> [String: Bool] {
        guard !uris.isEmpty,
              let data = run(["library", "contains"] + uris + ["--format", "json"]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let map = obj["contains"] as? [String: Bool] else { return [:] }
        return map
    }

    /// Cover image URLs for many URIs (tracks or playlists) in ONE call →
    /// uri:image_url map. Only the URL is fetched here; the image itself is
    /// loaded lazily per visible row via ArtworkCache.
    static func imageURLs(_ uris: [String]) -> [String: String] {
        guard !uris.isEmpty,
              let data = run(["lookup"] + uris + ["--format", "json"]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entities = obj["entities"] as? [[String: Any]] else { return [:] }
        var result: [String: String] = [:]
        for e in entities {
            if let uri = e["uri"] as? String, let img = e["image_url"] as? String { result[uri] = img }
        }
        return result
    }

    /// Resolve a track URI to its artist + album URIs (for click-to-open).
    static func links(forTrack uri: String) -> (artist: String?, album: String?) {
        guard let data = run(["lookup", uri, "--format", "json"]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entities = obj["entities"] as? [[String: Any]],
              let entity = entities.first else { return (nil, nil) }
        let album = (entity["parent"] as? [String: Any])?["uri"] as? String
        let artist = ((entity["contributors"] as? [[String: Any]])?.first)?["uri"] as? String
        return (artist, album)
    }

    /// Open a spotify: URI in the desktop app.
    static func open(_ uri: String) {
        guard let url = URL(string: uri) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Playlist browsing

    /// The user's playlists (saved + followed), in their library order.
    static func playlists() -> [PlaylistRef] {
        guard let data = run(["library", "list", "--type", "playlist", "--limit", "200", "--format", "json"]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let uri = item["uri"] as? String, let name = item["name"] as? String else { return nil }
            return PlaylistRef(id: uri, name: name, source: .spotify)
        }
    }

    /// The tracks inside a playlist (capped — these can be huge).
    static func tracks(inPlaylist uri: String) -> [PlaylistTrackRef] {
        guard let data = run(["playlist", "get", uri, "--limit", "300", "--format", "json"]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tracks = obj["tracks"] as? [[String: Any]] else { return [] }
        return tracks.compactMap { t in
            guard let tURI = t["uri"] as? String, let name = t["name"] as? String else { return nil }
            let artists = (t["artists"] as? [String]) ?? []
            return PlaylistTrackRef(id: tURI, name: name, artist: artists.joined(separator: ", "), source: .spotify)
        }
    }

    /// Start playing a context (playlist/album) or a single track URI.
    static func play(uri: String) { run(["play", uri]) }

    static func setShuffle(_ on: Bool) { run(["shuffle", on ? "on" : "off"]) }

    static func setRepeat(_ mode: RepeatMode) {
        let arg: String
        switch mode {
        case .off: arg = "off"
        case .all: arg = "context"
        case .one: arg = "track"
        }
        run(["repeat", arg])
    }
}
