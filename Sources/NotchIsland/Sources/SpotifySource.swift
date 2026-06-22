import ScriptingBridge
import AppKit

final class SpotifySource: NowPlayingSource {
    let kind: SourceKind = .spotify
    let canSetLiked = SpotifyCLI.isAvailable

    private let bundleID = "com.spotify.client"
    private lazy var app: SpotifyApplication? =
        SBApplication(bundleIdentifier: bundleID) as? SpotifyApplication

    var isRunning: Bool { app?.isRunning ?? false }

    // The slow bits (cover over the network, like-state via spotify_cli) are
    // fetched ASYNCHRONOUSLY and cached, so currentTrack() returns metadata
    // immediately — the island peeks the instant the track changes, and the
    // cover / heart fill in on the next poll.
    private let lock = NSLock()
    private var artID: String?
    private var art: NSImage?
    private var fetchingArt: String?
    private var likeID: String?
    private var liked: Bool?
    private var fetchingLike: String?
    private var pollCount = 0

    func currentTrack() -> Track? {
        guard isRunning, let t = app?.currentTrack else { return nil }
        guard let id = t.id else { return nil }
        guard let name = t.name else { return nil }

        lock.lock()
        pollCount += 1
        // Re-check like state periodically (~every 4s) so a like made directly
        // in Spotify is reflected here too.
        let likeStale = pollCount % 8 == 0
        let cachedArt = (artID == id) ? art : nil
        let cachedLiked = (likeID == id) ? liked : nil
        let needArt = artID != id && fetchingArt != id
        let needLike = canSetLiked && (likeID != id || likeStale) && fetchingLike != id
        if needArt { fetchingArt = id }
        if needLike { fetchingLike = id }
        lock.unlock()

        if needArt { fetchArtwork(id: id, urlString: t.artworkUrl) }
        if needLike { fetchLiked(id: id) }

        return Track(
            id: id,
            title: name,
            artist: t.artist ?? "",
            album: t.album ?? "",
            duration: Double(t.duration ?? 0) / 1000.0,
            artwork: cachedArt,
            isLiked: cachedLiked
        )
    }

    private func fetchArtwork(id: String, urlString: String?) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var image: NSImage?
            if let urlString, let url = URL(string: urlString),
               let data = try? Data(contentsOf: url) {
                image = NSImage(data: data)
            }
            guard let self else { return }
            self.lock.lock()
            self.art = image; self.artID = id; self.fetchingArt = nil
            self.lock.unlock()
        }
    }

    private func fetchLiked(id: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let value = SpotifyCLI.isLiked(id)
            guard let self else { return }
            self.lock.lock()
            self.liked = value; self.likeID = id; self.fetchingLike = nil
            self.lock.unlock()
        }
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

    func setLiked(_ liked: Bool) {
        // Called off-main by the coordinator; read the live URI for accuracy.
        guard let uri = app?.currentTrack?.id else { return }
        lock.lock(); self.liked = liked; self.likeID = uri; lock.unlock()
        SpotifyCLI.setLiked(uri, liked)
    }
}
