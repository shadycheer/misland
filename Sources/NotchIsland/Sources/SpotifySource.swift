import ScriptingBridge
import AppKit

final class SpotifySource: NowPlayingSource {
    let kind: SourceKind = .spotify
    let canSetLiked = false   // no local API in v1

    private let bundleID = "com.spotify.client"
    // Create the SBApplication ONCE. Re-creating it per access reloads the SDEF
    // and re-resolves the app via LaunchServices every time — that was the CPU sink.
    private lazy var app: SpotifyApplication? =
        SBApplication(bundleIdentifier: bundleID) as? SpotifyApplication

    var isRunning: Bool { app?.isRunning ?? false }

    // Cache the whole Track keyed by id; re-read the full metadata (and fetch
    // the cover) only when the track changes. Unchanged polls cost one Apple
    // Event (the id check).
    private var cachedID: String?
    private var cachedTrack: Track?

    func currentTrack() -> Track? {
        guard isRunning, let t = app?.currentTrack else { return nil }
        guard let id = t.id else { return nil }   // 1 Apple Event
        if id == cachedID, let cached = cachedTrack { return cached }

        guard let name = t.name else { return nil }
        // Runs on the poll queue (off-main), so a synchronous cover fetch is fine.
        var artwork: NSImage?
        if let urlStr = t.artworkUrl, let url = URL(string: urlStr),
           let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
            artwork = img
        }
        let track = Track(
            id: id,
            title: name,
            artist: t.artist ?? "",
            album: t.album ?? "",
            duration: Double(t.duration ?? 0) / 1000.0,
            artwork: artwork,
            isLiked: nil
        )
        // Lock the cache only once the cover is in, else retry next poll.
        if artwork != nil { cachedID = id; cachedTrack = track } else { cachedID = nil }
        return track
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
