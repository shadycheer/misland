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

    // Each SBObject property read is a separate synchronous Apple Event. Track
    // metadata only changes on track change, so cache the whole Track keyed by
    // id and re-read the full set only when the id changes. Unchanged polls cost
    // a single Apple Event (the id check).
    private var cachedID: String?
    private var cachedTrack: Track?

    func currentTrack() -> Track? {
        guard isRunning, let t = app?.currentTrack else { return nil }
        guard let id = t.id.map(String.init) else { return nil }   // 1 Apple Event
        // Read like state FRESH every poll (cheap local AE) — caching it freezes
        // the heart, so un-liking would snap back on the next tick.
        let fav = t.favorited ?? false

        if id == cachedID, var cached = cachedTrack {
            cached.isLiked = fav
            return cached
        }

        guard let name = t.name else { return nil }
        let artwork = artworkImage(of: t)
        let track = Track(
            id: id,
            title: name,
            artist: t.artist ?? "",
            album: t.album ?? "",
            duration: t.duration ?? 0,
            artwork: artwork,
            isLiked: fav
        )
        // Lock the cache only once artwork is present (Music returns it late);
        // otherwise leave it so the next poll re-reads until the cover arrives.
        if artwork != nil { cachedID = id; cachedTrack = track } else { cachedID = nil }
        return track
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
