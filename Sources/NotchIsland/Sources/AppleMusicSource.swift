import ScriptingBridge
import AppKit

final class AppleMusicSource: NowPlayingSource {
    let kind: SourceKind = .appleMusic
    let canSetLiked = true

    private let bundleID = "com.apple.Music"
    private var app: MusicApplication? {
        SBApplication(bundleIdentifier: bundleID) as? MusicApplication
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == bundleID }
    }

    // Artwork is expensive to read/decode; cache it per track id so the 1s
    // refresh tick doesn't re-fetch it every second.
    private var artCacheID: String?
    private var artCache: NSImage?

    func currentTrack() -> Track? {
        guard isRunning, let t = app?.currentTrack, let name = t.name else { return nil }
        let id = t.id.map(String.init) ?? name
        if id != artCacheID {
            // Music.app often returns no artwork for the first moment after a
            // track starts. Only lock the cache once we actually have an image;
            // until then keep retrying (and don't show the previous cover).
            if let art = t.artworks?.first?.data {
                artCacheID = id
                artCache = art
            } else {
                artCache = nil
            }
        }
        return Track(
            id: id,
            title: name,
            artist: t.artist ?? "",
            album: t.album ?? "",
            duration: t.duration ?? 0,
            artwork: artCache,
            isLiked: t.loved ?? false
        )
    }

    func currentState() -> PlaybackState? {
        guard isRunning, let app else { return nil }
        return PlaybackState(
            isPlaying: app.playerState == .playing,
            position: app.playerPosition ?? 0,
            source: .appleMusic
        )
    }

    func playPause() { app?.playpause?() }
    func next() { app?.nextTrack?() }
    func previous() { app?.previousTrack?() }
    func seek(to position: TimeInterval) {
        (app as? SBApplication)?.setValue(position, forKey: "playerPosition")
    }
    func setLiked(_ liked: Bool) {
        guard let t = app?.currentTrack as? SBObject else { return }
        t.setValue(liked, forKey: "loved")
    }
}
