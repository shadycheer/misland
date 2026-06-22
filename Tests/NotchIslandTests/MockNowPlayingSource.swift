@testable import NotchIsland
import Foundation

final class MockNowPlayingSource: NowPlayingSource {
    let kind: SourceKind
    var isRunning: Bool
    var track: Track?
    var state: PlaybackState?
    var canSetLiked: Bool

    private(set) var playPauseCalls = 0
    private(set) var nextCalls = 0
    private(set) var previousCalls = 0
    private(set) var seekedTo: TimeInterval?
    private(set) var likedSetTo: Bool?

    init(kind: SourceKind, isRunning: Bool = true, canSetLiked: Bool = true) {
        self.kind = kind
        self.isRunning = isRunning
        self.canSetLiked = canSetLiked
    }

    func currentTrack() -> Track? { track }
    func currentState() -> PlaybackState? { state }
    func playPause() { playPauseCalls += 1 }
    func next() { nextCalls += 1 }
    func previous() { previousCalls += 1 }
    func seek(to position: TimeInterval) { seekedTo = position }
    func setLiked(_ liked: Bool) { likedSetTo = liked }
}
