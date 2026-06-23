import AppKit

// MARK: - Models

/// A playlist row in the browser (level 1).
struct PlaylistRef: Identifiable, Equatable {
    let id: String          // Spotify: playlist URI · Apple Music: persistent ID
    let name: String
    let source: SourceKind
}

/// A song row inside a playlist (level 2).
struct PlaylistTrackRef: Identifiable, Equatable {
    let id: String          // Spotify: track URI · Apple Music: 1-based index in playlist
    let name: String
    let artist: String
    let source: SourceKind
    var liked: Bool?        // Apple Music reports it inline; Spotify is filled by a batch check
}

/// Repeat mode, mapped per-player in the service.
enum RepeatMode: CaseIterable { case off, all, one }

/// Where a row's cover comes from. Spotify covers are remote URLs; Apple Music
/// covers are local (read via ScriptingBridge). `none` shows a placeholder.
enum CoverSource: Equatable {
    case none
    case url(String)
    case appleMusicTrack(playlistID: String, index: Int)
    case appleMusicPlaylist(playlistID: String)
}

// MARK: - Service

/// Local-only playlist browsing + control. Spotify goes through the bundled
/// `spotify_cli`; Apple Music through AppleScript. Everything here is
/// synchronous IPC — ALWAYS call off the main thread.
enum PlaylistService {
    static func playlists(_ source: SourceKind) -> [PlaylistRef] {
        switch source {
        case .spotify:    return SpotifyCLI.playlists()
        case .appleMusic: return AppleMusicScript.playlists()
        }
    }

    static func tracks(in playlist: PlaylistRef) -> [PlaylistTrackRef] {
        switch playlist.source {
        case .spotify:    return SpotifyCLI.tracks(inPlaylist: playlist.id)
        case .appleMusic: return AppleMusicScript.tracks(inPlaylistID: playlist.id)
        }
    }

    /// Play the whole playlist from the top (respects current shuffle).
    static func play(playlist: PlaylistRef) {
        switch playlist.source {
        case .spotify:    SpotifyCLI.play(uri: playlist.id)
        case .appleMusic: AppleMusicScript.playPlaylist(id: playlist.id)
        }
    }

    /// Play one specific song.
    static func play(track: PlaylistTrackRef, in playlist: PlaylistRef) {
        switch track.source {
        case .spotify:
            SpotifyCLI.play(uri: track.id)
        case .appleMusic:
            if let i = Int(track.id) { AppleMusicScript.playTrack(index: i, inPlaylistID: playlist.id) }
        }
    }

    static func setShuffle(_ on: Bool, for source: SourceKind) {
        switch source {
        case .spotify:    SpotifyCLI.setShuffle(on)
        case .appleMusic: AppleMusicScript.setShuffle(on)
        }
    }

    static func setRepeat(_ mode: RepeatMode, for source: SourceKind) {
        switch source {
        case .spotify:    SpotifyCLI.setRepeat(mode)
        case .appleMusic: AppleMusicScript.setRepeat(mode)
        }
    }

    // MARK: - Per-row enrichment (liked status + cover URLs)

    /// Liked-status for a page of tracks → id:isLiked. Spotify batches one call;
    /// Apple Music already carries it inline from the track query.
    static func likedStatus(for tracks: [PlaylistTrackRef]) -> [String: Bool] {
        guard let first = tracks.first else { return [:] }
        switch first.source {
        case .spotify:
            return SpotifyCLI.contains(tracks.map { $0.id })
        case .appleMusic:
            var map: [String: Bool] = [:]
            for t in tracks { if let l = t.liked { map[t.id] = l } }
            return map
        }
    }

    /// Cover URLs for a page of tracks → id:url (Spotify only; Apple Music art is
    /// local and not exposed as a URL).
    static func coverURLs(for tracks: [PlaylistTrackRef]) -> [String: String] {
        guard let first = tracks.first, first.source == .spotify else { return [:] }
        return SpotifyCLI.imageURLs(tracks.map { $0.id })
    }

    /// Cover URLs for playlist rows → id:url (Spotify only).
    static func coverURLs(forPlaylists playlists: [PlaylistRef]) -> [String: String] {
        guard let first = playlists.first, first.source == .spotify else { return [:] }
        return SpotifyCLI.imageURLs(playlists.map { $0.id })
    }

    static func setLiked(_ liked: Bool, for track: PlaylistTrackRef, in playlist: PlaylistRef?) {
        switch track.source {
        case .spotify:
            SpotifyCLI.setLiked(track.id, liked)
        case .appleMusic:
            if let playlist, let i = Int(track.id) {
                AppleMusicScript.setFavorite(index: i, inPlaylistID: playlist.id, liked)
            }
        }
    }
}

// MARK: - Apple Music AppleScript

/// Thin AppleScript wrapper for Music.app playlist browsing/control.
/// All calls are synchronous; run off the main thread.
private enum AppleMusicScript {
    /// Run an AppleScript and return stdout (trimmed), or nil on error.
    private static func run(_ script: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rows separated by ASCII record-separator, fields by unit-separator —
    /// avoids collisions with tabs/newlines inside track or playlist names.
    private static let rowSep = "\u{1e}"
    private static let fieldSep = "\u{1f}"

    static func playlists() -> [PlaylistRef] {
        let script = """
        tell application "Music"
            set out to ""
            repeat with p in user playlists
                try
                    set out to out & (name of p) & "\(fieldSep)" & (persistent ID of p) & "\(rowSep)"
                end try
            end repeat
            return out
        end tell
        """
        guard let raw = run(script) else { return [] }
        return raw.components(separatedBy: rowSep).compactMap { row in
            let f = row.components(separatedBy: fieldSep)
            guard f.count == 2, !f[0].isEmpty else { return nil }
            return PlaylistRef(id: f[1], name: f[0], source: .appleMusic)
        }
    }

    static func tracks(inPlaylistID id: String) -> [PlaylistTrackRef] {
        // Cap at 300 to match Spotify and keep the script fast on huge libraries.
        let script = """
        tell application "Music"
            set pl to (first user playlist whose persistent ID is "\(id)")
            set out to ""
            set total to (count of tracks of pl)
            set lim to 300
            if total < lim then set lim to total
            repeat with i from 1 to lim
                try
                    set t to track i of pl
                    set out to out & i & "\(fieldSep)" & (name of t) & "\(fieldSep)" & (artist of t) & "\(fieldSep)" & (favorited of t) & "\(rowSep)"
                end try
            end repeat
            return out
        end tell
        """
        guard let raw = run(script) else { return [] }
        return raw.components(separatedBy: rowSep).compactMap { row in
            let f = row.components(separatedBy: fieldSep)
            guard f.count == 4, !f[0].isEmpty else { return nil }
            return PlaylistTrackRef(id: f[0], name: f[1], artist: f[2],
                                    source: .appleMusic, liked: f[3] == "true")
        }
    }

    static func setFavorite(index: Int, inPlaylistID id: String, _ on: Bool) {
        _ = run("""
        tell application "Music"
            set pl to (first user playlist whose persistent ID is "\(id)")
            set favorited of track \(index) of pl to \(on ? "true" : "false")
        end tell
        """)
    }

    static func playPlaylist(id: String) {
        _ = run("""
        tell application "Music" to play (first user playlist whose persistent ID is "\(id)")
        """)
    }

    static func playTrack(index: Int, inPlaylistID id: String) {
        _ = run("""
        tell application "Music"
            set pl to (first user playlist whose persistent ID is "\(id)")
            play track \(index) of pl
        end tell
        """)
    }

    static func setShuffle(_ on: Bool) {
        _ = run("tell application \"Music\" to set shuffle enabled to \(on ? "true" : "false")")
    }

    static func setRepeat(_ mode: RepeatMode) {
        let v: String
        switch mode {
        case .off: v = "off"
        case .all: v = "all"
        case .one: v = "one"
        }
        _ = run("tell application \"Music\" to set song repeat to \(v)")
    }
}
