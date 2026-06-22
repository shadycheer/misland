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

    func currentTrack() -> Track? {
        guard isRunning, let t = app?.currentTrack, let name = t.name else { return nil }
        let durMs = t.duration ?? 0
        var artwork: NSImage?
        if let urlStr = t.artworkUrl, let url = URL(string: urlStr),
           let data = try? Data(contentsOf: url) {
            artwork = NSImage(data: data)
        }
        return Track(
            id: t.id ?? name,
            title: name,
            artist: t.artist ?? "",
            album: t.album ?? "",
            duration: Double(durMs) / 1000.0,
            artwork: artwork,
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
