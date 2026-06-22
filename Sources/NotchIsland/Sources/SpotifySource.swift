import ScriptingBridge
import AppKit

final class SpotifySource: NowPlayingSource {
    let kind: SourceKind = .spotify
    let canSetLiked = false   // no local API in v1

    private let bundleID = "com.spotify.client"
    private var app: SpotifyApplication? {
        SBApplication(bundleIdentifier: bundleID) as? SpotifyApplication
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == bundleID }
    }

    // Artwork comes over the network for Spotify — fetch once per track on a
    // background queue and cache it, never on the 1s refresh tick.
    private var artCacheID: String?
    private var artCache: NSImage?

    func currentTrack() -> Track? {
        guard isRunning, let t = app?.currentTrack, let name = t.name else { return nil }
        let id = t.id ?? name
        let durMs = t.duration ?? 0
        if id != artCacheID {
            // currentTrack() runs on the poll queue (off-main), so a synchronous
            // fetch here is fine. Only lock the cache once we actually have an
            // image, so a not-yet-ready / failed url is retried next tick.
            artCache = nil
            if let urlStr = t.artworkUrl, let url = URL(string: urlStr),
               let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
                artCacheID = id
                artCache = img
            }
        }
        return Track(
            id: id,
            title: name,
            artist: t.artist ?? "",
            album: t.album ?? "",
            duration: Double(durMs) / 1000.0,
            artwork: artCache,
            isLiked: nil
        )
    }

    func currentState() -> PlaybackState? {
        guard isRunning, let app else { return nil }
        return PlaybackState(
            isPlaying: app.playerState == .playing,
            position: app.playerPosition ?? 0,
            source: .spotify
        )
    }

    func playPause() { app?.playpause?() }
    func next() { app?.nextTrack?() }
    func previous() { app?.previousTrack?() }
    func seek(to position: TimeInterval) {
        (app as? SBApplication)?.setValue(position, forKey: "playerPosition")
    }
    func setLiked(_ liked: Bool) { /* unsupported in v1 */ }
}
