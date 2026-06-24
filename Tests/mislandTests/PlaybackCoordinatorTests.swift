@testable import misland
import XCTest

final class PlaybackCoordinatorTests: XCTestCase {

    private func makeTrack(_ id: String) -> Track {
        Track(id: id, title: "t", artist: "a", album: "al", duration: 100, artwork: nil, isLiked: nil)
    }

    func test_picksTheRunningPlayingSource() {
        let spotify = MockNowPlayingSource(kind: .spotify, isRunning: false)
        let music = MockNowPlayingSource(kind: .appleMusic, isRunning: true)
        music.track = makeTrack("m1")
        music.state = PlaybackState(isPlaying: true, position: 5, source: .appleMusic)

        let c = PlaybackCoordinator(sources: [spotify, music])
        c.refresh()

        XCTAssertEqual(c.track, music.track)
        XCTAssertEqual(c.state?.source, .appleMusic)
    }

    func test_whenBothPlaying_mostRecentlyChangedWins() {
        let spotify = MockNowPlayingSource(kind: .spotify)
        let music = MockNowPlayingSource(kind: .appleMusic)
        spotify.track = makeTrack("s1")
        spotify.state = PlaybackState(isPlaying: true, position: 0, source: .spotify)
        music.track = makeTrack("m1")
        music.state = PlaybackState(isPlaying: true, position: 0, source: .appleMusic)

        let c = PlaybackCoordinator(sources: [spotify, music])
        c.refresh()                          // spotify becomes active (first playing)
        spotify.track = makeTrack("s2")      // spotify changes track most recently
        c.sourceDidSignal(.spotify)
        c.refresh()

        XCTAssertEqual(c.state?.source, .spotify)
    }

    func test_controlsRouteToActiveSource() {
        let music = MockNowPlayingSource(kind: .appleMusic)
        music.track = makeTrack("m1")
        music.state = PlaybackState(isPlaying: true, position: 0, source: .appleMusic)
        let c = PlaybackCoordinator(sources: [music])
        c.refresh()

        c.playPause(); c.next(); c.previous(); c.seek(to: 42)

        let controls = expectation(description: "controls off-main")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { controls.fulfill() }
        wait(for: [controls], timeout: 1)

        XCTAssertEqual(music.playPauseCalls, 1)
        XCTAssertEqual(music.nextCalls, 1)
        XCTAssertEqual(music.previousCalls, 1)
        XCTAssertEqual(music.seekedTo, 42)

        c.toggleLike()
        XCTAssertEqual(c.track?.isLiked, true)   // optimistic update is synchronous
        // The source side-effect runs off-main; wait for it.
        let exp = expectation(description: "setLiked off-main")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(music.likedSetTo, true)
    }

    func test_whenActivePauses_fallsToTheOtherPlayingSource() {
        let spotify = MockNowPlayingSource(kind: .spotify)
        let music = MockNowPlayingSource(kind: .appleMusic)
        spotify.track = makeTrack("s1")
        spotify.state = PlaybackState(isPlaying: true, position: 0, source: .spotify)
        music.track = makeTrack("m1")
        music.state = PlaybackState(isPlaying: false, position: 0, source: .appleMusic)

        let c = PlaybackCoordinator(sources: [spotify, music])
        c.refresh()
        XCTAssertEqual(c.state?.source, .spotify)   // only spotify playing

        // Spotify pauses, Apple Music starts playing → island follows Apple Music.
        spotify.state = PlaybackState(isPlaying: false, position: 10, source: .spotify)
        music.state = PlaybackState(isPlaying: true, position: 0, source: .appleMusic)
        c.refresh()
        XCTAssertEqual(c.state?.source, .appleMusic)
    }

    func test_whenNonePlaying_mostRecentlyChangedTrackWins() {
        let spotify = MockNowPlayingSource(kind: .spotify)
        let qq = MockNowPlayingSource(kind: .qqMusic)
        spotify.track = makeTrack("s1")
        spotify.state = PlaybackState(isPlaying: false, position: 0, source: .spotify)
        qq.track = makeTrack("q1")
        qq.state = PlaybackState(isPlaying: false, position: 0, source: .qqMusic)

        let c = PlaybackCoordinator(sources: [spotify, qq])
        c.refresh()
        XCTAssertEqual(c.state?.source, .qqMusic)

        spotify.track = makeTrack("s2")
        c.refresh()
        XCTAssertEqual(c.state?.source, .spotify)
    }

    func test_noSourcePlaying_clearsTrack() {
        let spotify = MockNowPlayingSource(kind: .spotify, isRunning: false)
        let c = PlaybackCoordinator(sources: [spotify])
        c.refresh()
        XCTAssertNil(c.track)
        XCTAssertNil(c.state)
    }

    func test_exclusivePlayback_pausesTheOtherWhenOneStarts() {
        UserDefaults.standard.set(true, forKey: "exclusivePlayback")
        defer { UserDefaults.standard.removeObject(forKey: "exclusivePlayback") }
        let spotify = MockNowPlayingSource(kind: .spotify)
        let music = MockNowPlayingSource(kind: .appleMusic)
        spotify.track = makeTrack("s1")
        spotify.state = PlaybackState(isPlaying: true, position: 0, source: .spotify)
        music.track = makeTrack("m1")
        music.state = PlaybackState(isPlaying: false, position: 0, source: .appleMusic)

        let c = PlaybackCoordinator(sources: [spotify, music])
        c.refresh()                      // spotify playing, music paused
        XCTAssertEqual(spotify.pauseCalls, 0)

        music.state = PlaybackState(isPlaying: true, position: 0, source: .appleMusic)
        c.refresh()                      // music starts → spotify paused
        XCTAssertEqual(spotify.pauseCalls, 1)
    }
}
