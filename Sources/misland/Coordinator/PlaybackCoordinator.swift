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

    /// When on, starting one player pauses the others (only one plays at a time).
    @ObservationIgnored private var exclusivePlayback: Bool {
        UserDefaults.standard.bool(forKey: "exclusivePlayback")
    }

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
        // Stamp an activation whenever a source becomes playing or changes
        // track. Track changes also matter while paused: AX-only sources such
        // as QQ do not emit distributed notifications, and otherwise a paused
        // Spotify/Apple Music track earlier in the source list can mask them.
        for r in reads {
            let kind = r.source.kind
            let playing = r.state?.isPlaying ?? false
            let id = r.track?.id
            let was = prev[kind]
            if id != nil && (was?.playing != playing || was?.trackID != id) {
                tick += 1
                activation[kind] = tick
            }
            prev[kind] = (playing, id)
        }
        let active = selectActive(reads)
        writeDebugSnapshot(reads: reads, active: active)
        activeKind = active?.source.kind
        // Exclusive playback (idempotent): pause every playing source that isn't
        // the active one. The active source is stable (most-recently-activated),
        // so this can't ping-pong — it just keeps the non-active ones paused.
        if exclusivePlayback, let active {
            for r in reads where r.source.kind != active.source.kind && r.state?.isPlaying == true {
                r.source.pause()
            }
        }
        if let active, let t = active.track {
            let state = active.state ?? PlaybackState(
                isPlaying: false,
                position: 0,
                source: active.source.kind
            )
            return Snapshot(track: t, state: state, canLike: active.source.canSetLiked)
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
        let withTrack = reads.filter { $0.track != nil }
        return withTrack.max(by: {
            (activation[$0.source.kind] ?? 0) < (activation[$1.source.kind] ?? 0)
        })
    }

    /// Apply a snapshot to the observable state. MAIN THREAD ONLY.
    func publish(_ s: Snapshot) {
        if s.track != track { track = s.track }
        if s.state != state { state = s.state }
        if s.canLike != canLike { canLike = s.canLike }
        if let track = s.track, let source = s.state?.source {
            PlaybackHistoryStore.shared.record(track: track, source: source)
        }
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

    func playPause() {
        guard let s = activeSource else { return }
        if var current = state, current.source == s.kind {
            current.isPlaying.toggle()
            current.sampledAt = Date()
            state = current
        }
        DispatchQueue.global(qos: .userInitiated).async { s.playPause() }
    }

    func next() {
        guard let s = activeSource else { return }
        DispatchQueue.global(qos: .userInitiated).async { s.next() }
    }

    func previous() {
        guard let s = activeSource else { return }
        DispatchQueue.global(qos: .userInitiated).async { s.previous() }
    }

    func seek(to position: TimeInterval) {
        guard let s = activeSource else { return }
        if var current = state, current.source == s.kind {
            let duration = track?.duration ?? 0
            current.position = duration > 0 ? min(max(position, 0), duration) : max(position, 0)
            current.sampledAt = Date()
            state = current
        }
        DispatchQueue.global(qos: .userInitiated).async { s.seek(to: position) }
    }

    func toggleLike() {
        guard let s = activeSource, s.canSetLiked else { return }
        let next = !(track?.isLiked ?? false)
        track?.isLiked = next                       // optimistic, instant
        DispatchQueue.global(qos: .userInitiated).async { s.setLiked(next) } // off-main
    }

    // MARK: - Selection

    private var activeSource: NowPlayingSource? {
        activeKind.flatMap(source(for:))
    }

    private func source(for kind: SourceKind) -> NowPlayingSource? {
        sources.first { $0.kind == kind }
    }

    private func writeDebugSnapshot(reads: [Read], active: Read?) {
        let flag = URL(fileURLWithPath: "/tmp/misland-debug-on")
        guard FileManager.default.fileExists(atPath: flag.path) else { return }
        var lines: [String] = [
            "time=\(Date())",
            "active=\(active?.source.kind.rawValue ?? "nil")",
        ]
        for r in reads {
            lines.append([
                "source=\(r.source.kind.rawValue)",
                "running=\(r.source.isRunning)",
                "track=\(r.track.map { "\($0.title) - \($0.artist)" } ?? "nil")",
                "trackID=\(r.track?.id ?? "nil")",
                "album=\(r.track?.album ?? "nil")",
                "duration=\(r.track.map { String(Int($0.duration)) } ?? "nil")",
                "artwork=\(r.track?.artwork == nil ? "nil" : "yes")",
                "position=\(r.state.map { String(format: "%.1f", $0.position) } ?? "nil")",
                "playing=\(r.state.map { String($0.isPlaying) } ?? "nil")",
                "canLike=\(r.source.canSetLiked)",
            ].joined(separator: " "))
        }
        try? (lines.joined(separator: "\n") + "\n").write(
            to: URL(fileURLWithPath: "/tmp/misland-source-snapshot.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
