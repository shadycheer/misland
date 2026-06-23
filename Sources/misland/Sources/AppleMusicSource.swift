import ScriptingBridge
import AppKit

final class AppleMusicSource: NowPlayingSource {
    let kind: SourceKind = .appleMusic
    let canSetLiked = true

    private let bundleID = "com.apple.Music"
    // Create the SBApplication ONCE (see SpotifySource for why).
    private lazy var app: MusicApplication? =
        SBApplication(bundleIdentifier: bundleID) as? MusicApplication

    var isRunning: Bool { app?.isRunning ?? false }

    // Resolved cover cached per track (a stable NSImage instance, so the UI
    // doesn't re-render every poll). Local/embedded art is used first; on a miss
    // (streaming tracks expose no bytes) we fall back to the iTunes Search API.
    private let lock = NSLock()
    private var artID: String?
    private var art: NSImage?

    func currentTrack() -> Track? {
        guard isRunning, let t = app?.currentTrack else { return nil }
        guard let id = t.id.map(String.init) else { return nil }
        guard let name = t.name else { return nil }
        let fav = t.favorited ?? false       // fresh every poll so un-like syncs
        let artist = t.artist ?? ""

        // Local/embedded artwork only — no network. Cache once found (stable
        // NSImage instance so the UI doesn't re-render every poll); retry next
        // poll while still nil (Music sometimes provides it a beat late).
        lock.lock()
        var artwork = (artID == id) ? art : nil
        lock.unlock()
        if artwork == nil, let local = artworkImage(of: t) {
            artwork = local
            lock.lock(); art = local; artID = id; lock.unlock()
        }

        return Track(id: id, title: name, artist: artist, album: t.album ?? "",
                     duration: t.duration ?? 0, artwork: artwork, isLiked: fav)
    }

    /// Defensive artwork read. Bridging Music's `artworks` to `[MusicArtwork]`
    /// and taking `.first` traps (`_getElementSlowPath`) for items with no/odd
    /// artwork (radio, non-library tracks). Go through NSArray + KVC instead.
    private func artworkImage(of track: MusicTrack) -> NSImage? {
        guard let sb = track as? SBObject,
              let arr = sb.value(forKey: "artworks") as? NSArray,
              arr.count > 0,
              let first = arr.object(at: 0) as? NSObject else { return nil }
        // `data` is usually a TIFF NSImage, but local files sometimes expose the
        // bytes via `rawData` (NSData) instead — try both.
        if let img = first.value(forKey: "data") as? NSImage, img.isValid { return img }
        if let data = first.value(forKey: "data") as? Data, let img = NSImage(data: data) { return img }
        if let raw = first.value(forKey: "rawData") as? Data, let img = NSImage(data: raw) { return img }
        return nil
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
    func pause() { app?.pause?() }
    func next() { app?.nextTrack?() }
    func previous() { app?.previousTrack?() }
    func seek(to position: TimeInterval) {
        (app as? SBApplication)?.setValue(position, forKey: "playerPosition")
    }
    func setLiked(_ liked: Bool) {
        guard let t = app?.currentTrack as? SBObject else { return }
        t.setValue(liked, forKey: "favorited")  // 'loved' was renamed; wrong key threw NSUnknownKeyException
    }
}
