import Foundation

protocol NowPlayingSource: AnyObject {
    var kind: SourceKind { get }
    var isRunning: Bool { get }

    /// Snapshot current track, or nil if nothing playing / app not running.
    func currentTrack() -> Track?
    /// Snapshot current playback state, or nil if unavailable.
    func currentState() -> PlaybackState?

    func playPause()
    func next()
    func previous()
    func seek(to position: TimeInterval)

    /// True if this source can set "like". Spotify returns false in v1.
    var canSetLiked: Bool { get }
    func setLiked(_ liked: Bool)
}
