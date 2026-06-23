import ScriptingBridge
import AppKit

/// Pulls LOCAL artwork for arbitrary Apple Music playlist tracks via
/// ScriptingBridge (no network, no AppleScript binary round-trip). Used by the
/// playlist browser's lazy row covers; results are memoized in ArtworkCache, so
/// each cover is read at most once. All calls are synchronous IPC — invoke OFF
/// the main thread (ArtworkCache does this for us).
enum AppleMusicArtwork {
    private static let lock = NSLock()
    private static var cachedApp: SBApplication?

    /// Cached SBApplication (recreating it per call is expensive — see SpotifySource).
    private static var app: SBApplication? {
        lock.lock(); defer { lock.unlock() }
        // Don't launch Music just to read a thumbnail.
        guard NSWorkspace.shared.runningApplications
            .contains(where: { $0.bundleIdentifier == "com.apple.Music" }) else { return nil }
        if cachedApp == nil { cachedApp = SBApplication(bundleIdentifier: "com.apple.Music") }
        return cachedApp
    }

    /// Artwork for the `index`-th (1-based) track of the playlist with this
    /// persistent ID.
    static func trackImage(playlistID: String, index: Int) -> NSImage? {
        guard index >= 1, let pl = playlist(persistentID: playlistID),
              let tracks = pl.value(forKey: "tracks") as? SBElementArray,
              index <= tracks.count,
              let track = tracks.object(at: index - 1) as? SBObject else { return nil }
        return artwork(of: track)
    }

    /// A representative cover for a playlist — its first track's artwork.
    static func playlistImage(playlistID: String) -> NSImage? {
        trackImage(playlistID: playlistID, index: 1)
    }

    private static func playlist(persistentID: String) -> SBObject? {
        guard let app, let playlists = app.value(forKey: "userPlaylists") as? SBElementArray else { return nil }
        for case let pl as SBObject in playlists {
            if (pl.value(forKey: "persistentID") as? String) == persistentID { return pl }
        }
        return nil
    }

    /// Same defensive read as AppleMusicSource (NSArray + KVC; bridging to
    /// [MusicArtwork].first traps for odd/empty artwork).
    private static func artwork(of track: SBObject) -> NSImage? {
        guard let arr = track.value(forKey: "artworks") as? NSArray,
              arr.count > 0, let first = arr.object(at: 0) as? NSObject else { return nil }
        if let img = first.value(forKey: "data") as? NSImage, img.isValid { return img }
        if let data = first.value(forKey: "data") as? Data, let img = NSImage(data: data) { return img }
        if let raw = first.value(forKey: "rawData") as? Data, let img = NSImage(data: raw) { return img }
        return nil
    }
}
