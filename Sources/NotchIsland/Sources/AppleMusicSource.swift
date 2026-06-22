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

    func currentTrack() -> Track? {
        guard isRunning, let t = app?.currentTrack, let name = t.name else { return nil }
        var artwork: NSImage?
        if let arts = t.artworks, let first = arts.first { artwork = first.data }
        return Track(
            id: t.id.map(String.init) ?? name,
            title: name,
            artist: t.artist ?? "",
            album: t.album ?? "",
            duration: t.duration ?? 0,
            artwork: artwork,
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
