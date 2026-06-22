import Observation
import Foundation

@Observable
final class PlaybackCoordinator {
    private(set) var track: Track?
    private(set) var state: PlaybackState?
    private(set) var canLike: Bool = false

    @ObservationIgnored private let sources: [NowPlayingSource]
    @ObservationIgnored private var activeKind: SourceKind?
    // "Most recently active wins": a monotonic counter stamped whenever a source
    // starts playing or changes track. Highest stamp among playing sources wins.
    @ObservationIgnored private var prev: [SourceKind: (playing: Bool, trackID: String?)] = [:]
    @ObservationIgnored private var activation: [SourceKind: Int] = [:]
    @ObservationIgnored private var tick = 0

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
        // Stamp an activation whenever a source becomes playing or changes track.
        for r in reads {
            let kind = r.source.kind
            let playing = r.state?.isPlaying ?? false
            let id = r.track?.id
            let was = prev[kind]
            if playing && (was?.playing != true || was?.trackID != id) {
                tick += 1
                activation[kind] = tick
            }
            prev[kind] = (playing, id)
        }
        let active = selectActive(reads)
        activeKind = active?.source.kind
        if let active, let t = active.track, let st = active.state {
            return Snapshot(track: t, state: st, canLike: active.source.canSetLiked)
        }
        return Snapshot(track: nil, state: nil, canLike: false)
    }

    /// Among currently-playing sources, the most recently activated wins. If
    /// none is playing, keep the last active (sticky); else the first with a track.
    private func selectActive(_ reads: [Read]) -> Read? {
        let playing = reads.filter { $0.state?.isPlaying == true }
        if let best = playing.max(by: {
            (activation[$0.source.kind] ?? 0) < (activation[$1.source.kind] ?? 0)
        }) {
            return best
        }
        if let k = activeKind, let r = reads.first(where: { $0.source.kind == k && $0.track != nil }) {
            return r
        }
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
        // A change notification = a fresh activation (validated against actual
        // playing state in selectActive, so signalling a paused source is safe).
        tick += 1
        activation[kind] = tick
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
