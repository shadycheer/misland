import Observation
import Foundation

@Observable
final class PlaybackCoordinator {
    private(set) var track: Track?
    private(set) var state: PlaybackState?
    private(set) var canLike: Bool = false

    @ObservationIgnored private let sources: [NowPlayingSource]
    @ObservationIgnored private var activeKind: SourceKind?

    init(sources: [NowPlayingSource]) {
        self.sources = sources
    }

    struct Snapshot {
        let track: Track?
        let state: PlaybackState?
        let canLike: Bool
    }

    /// Reads the players via ScriptingBridge. Call OFF the main thread (it does
    /// synchronous cross-process IPC) — serialize calls on one queue.
    func readSnapshot() -> Snapshot {
        let active = resolveActiveSource()
        activeKind = active?.kind
        if let active, let t = active.currentTrack(), let st = active.currentState() {
            return Snapshot(track: t, state: st, canLike: active.canSetLiked)
        }
        return Snapshot(track: nil, state: nil, canLike: false)
    }

    /// Apply a snapshot to the observable state. MAIN THREAD ONLY.
    func publish(_ s: Snapshot) {
        if s.track != track { track = s.track }
        if s.state != state { state = s.state }
        if s.canLike != canLike { canLike = s.canLike }
    }

    /// Synchronous read+publish — used by tests; the app polls off-main instead.
    func refresh() { publish(readSnapshot()) }

    /// Promote a source that just signalled a change (most-recently-active wins).
    /// Call on the same queue as `readSnapshot`.
    func sourceDidSignal(_ kind: SourceKind) {
        if let s = source(for: kind), s.isRunning, s.currentState()?.isPlaying == true {
            activeKind = kind
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
