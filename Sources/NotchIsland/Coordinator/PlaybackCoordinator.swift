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

    private struct Read {
        let source: NowPlayingSource
        let state: PlaybackState?
        let track: Track?
    }

    /// Reads the players via ScriptingBridge. Call OFF the main thread (it does
    /// synchronous cross-process IPC) — serialize calls on one queue.
    /// Each source is read at most ONCE per snapshot.
    func readSnapshot() -> Snapshot {
        let reads: [Read] = sources.map { src in
            guard src.isRunning else { return Read(source: src, state: nil, track: nil) }
            return Read(source: src, state: src.currentState(), track: src.currentTrack())
        }
        let active = selectActive(reads)
        activeKind = active?.source.kind
        if let active, let t = active.track, let st = active.state {
            return Snapshot(track: t, state: st, canLike: active.source.canSetLiked)
        }
        return Snapshot(track: nil, state: nil, canLike: false)
    }

    /// Sticky active source if still playing; else first playing; else first with a track.
    private func selectActive(_ reads: [Read]) -> Read? {
        if let k = activeKind, let r = reads.first(where: { $0.source.kind == k }),
           r.state?.isPlaying == true {
            return r
        }
        if let playing = reads.first(where: { $0.state?.isPlaying == true }) { return playing }
        return reads.first { $0.track != nil }
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
    /// readSnapshot validates it's still playing before honoring the stickiness.
    func sourceDidSignal(_ kind: SourceKind) {
        activeKind = kind
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
}
