import Observation
import Foundation

@Observable
final class PlaybackCoordinator {
    private(set) var track: Track?
    private(set) var state: PlaybackState?

    @ObservationIgnored private let sources: [NowPlayingSource]
    @ObservationIgnored private var activeKind: SourceKind?

    init(sources: [NowPlayingSource]) {
        self.sources = sources
    }

    /// Called when a source posts a change notification — promotes it so that,
    /// when several are playing, the most recently active wins.
    func sourceDidSignal(_ kind: SourceKind) {
        if let s = source(for: kind), s.isRunning, s.currentState()?.isPlaying == true {
            activeKind = kind
        }
    }

    func refresh() {
        let active = resolveActiveSource()
        activeKind = active?.kind
        if let active, let t = active.currentTrack(), let st = active.currentState() {
            // Assign only on change so the artwork Image isn't rebuilt every
            // tick. State (position) changes each tick — that's expected.
            if t != track { track = t }
            if st != state { state = st }
        } else {
            if track != nil { track = nil }
            if state != nil { state = nil }
        }
    }

    func playPause() { activeSource?.playPause() }
    func next() { activeSource?.next() }
    func previous() { activeSource?.previous() }
    func seek(to position: TimeInterval) { activeSource?.seek(to: position) }

    func toggleLike() {
        guard let s = activeSource, s.canSetLiked else { return }
        let current = track?.isLiked ?? false
        s.setLiked(!current)
        track?.isLiked = !current
    }

    // MARK: - Selection

    private var activeSource: NowPlayingSource? {
        activeKind.flatMap(source(for:))
    }

    private func source(for kind: SourceKind) -> NowPlayingSource? {
        sources.first { $0.kind == kind }
    }

    /// Active source = the sticky activeKind if it is still playing; else the
    /// first running+playing source; else the first running source with a track.
    private func resolveActiveSource() -> NowPlayingSource? {
        if let k = activeKind, let s = source(for: k),
           s.isRunning, s.currentState()?.isPlaying == true {
            return s
        }
        if let playing = sources.first(where: { $0.isRunning && $0.currentState()?.isPlaying == true }) {
            return playing
        }
        return sources.first { $0.isRunning && $0.currentTrack() != nil }
    }
}
