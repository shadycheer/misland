import AppKit

// MARK: - Models

/// A playlist row in the browser (level 1).
struct PlaylistRef: Identifiable, Equatable {
    let id: String          // Spotify: playlist URI · Apple Music: persistent ID
    let name: String
    let source: SourceKind
    var coverURL: String? = nil
}

/// A song row inside a playlist (level 2).
struct PlaylistTrackRef: Identifiable, Equatable {
    let id: String          // Spotify: track URI · Apple Music: 1-based index in playlist
    let name: String
    let artist: String
    let source: SourceKind
    var liked: Bool?        // Apple Music reports it inline; Spotify is filled by a batch check
    var artworkURL: String? = nil
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
/// `spotify_cli`; Apple Music through AppleScript; QQ/NetEase read local app
/// caches. Everything here is synchronous IPC — ALWAYS call off the main thread.
enum PlaylistService {
    static func canPlayFromBrowser(_ source: SourceKind) -> Bool {
        switch source {
        case .spotify, .appleMusic:
            return true
        case .qqMusic, .neteaseMusic:
            return false
        }
    }

    static func playlists(_ source: SourceKind) -> [PlaylistRef] {
        switch source {
        case .spotify:    return SpotifyCLI.playlists()
        case .appleMusic: return AppleMusicScript.playlists()
        case .qqMusic:
            return QQMusicArchiveMetadataStore.shared.currentQueue().isEmpty
                ? []
                : [PlaylistRef(id: "qq-current-queue", name: "QQ 音乐当前队列", source: .qqMusic)]
        case .neteaseMusic:
            return NetEaseMusicLibraryStore.shared.playlists().map {
                PlaylistRef(
                    id: String($0.id),
                    name: $0.name,
                    source: .neteaseMusic,
                    coverURL: $0.coverURL
                )
            }
        }
    }

    static func tracks(in playlist: PlaylistRef) -> [PlaylistTrackRef] {
        switch playlist.source {
        case .spotify:    return SpotifyCLI.tracks(inPlaylist: playlist.id)
        case .appleMusic: return AppleMusicScript.tracks(inPlaylistID: playlist.id)
        case .qqMusic:
            return QQMusicArchiveMetadataStore.shared.currentQueue().enumerated().map { index, item in
                PlaylistTrackRef(
                    id: item.songMid ?? item.songID.map(String.init) ?? "\(index)",
                    name: item.title,
                    artist: item.artist,
                    source: .qqMusic,
                    liked: nil
                )
            }
        case .neteaseMusic:
            guard let playlistID = Int64(playlist.id) else { return [] }
            return NetEaseMusicLibraryStore.shared.tracks(playlistID: playlistID).map {
                PlaylistTrackRef(
                    id: $0.stableID,
                    name: $0.title,
                    artist: $0.artist,
                    source: .neteaseMusic,
                    liked: nil,
                    artworkURL: $0.artworkURL
                )
            }
        }
    }

    /// Play the whole playlist from the top (respects current shuffle).
    static func play(playlist: PlaylistRef) {
        switch playlist.source {
        case .spotify:    SpotifyCLI.play(uri: playlist.id)
        case .appleMusic: AppleMusicScript.playPlaylist(id: playlist.id)
        case .qqMusic:    break
        case .neteaseMusic: break
        }
    }

    /// Play one specific song.
    static func play(track: PlaylistTrackRef, in playlist: PlaylistRef) {
        switch track.source {
        case .spotify:
            SpotifyCLI.play(uri: track.id)
        case .appleMusic:
            if let i = Int(track.id) { AppleMusicScript.playTrack(index: i, inPlaylistID: playlist.id) }
        case .qqMusic:
            break
        case .neteaseMusic:
            break
        }
    }

    static func setShuffle(_ on: Bool, for source: SourceKind) {
        switch source {
        case .spotify:    SpotifyCLI.setShuffle(on)
        case .appleMusic: AppleMusicScript.setShuffle(on)
        case .qqMusic:    break
        case .neteaseMusic: break
        }
    }

    static func setRepeat(_ mode: RepeatMode, for source: SourceKind) {
        switch source {
        case .spotify:    SpotifyCLI.setRepeat(mode)
        case .appleMusic: AppleMusicScript.setRepeat(mode)
        case .qqMusic:    break
        case .neteaseMusic: break
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
        case .qqMusic:
            return [:]
        case .neteaseMusic:
            let likedIDs = NetEaseMusicLibraryStore.shared.likedTrackIDs()
            var map: [String: Bool] = [:]
            for t in tracks {
                guard let id = t.id.split(separator: ":").last.flatMap({ Int64($0) }) else { continue }
                map[t.id] = likedIDs.contains(id)
            }
            return map
        }
    }

    /// Cover URLs for a page of tracks → id:url (Apple Music art is
    /// local and not exposed as a URL).
    static func coverURLs(for tracks: [PlaylistTrackRef]) -> [String: String] {
        guard let first = tracks.first else { return [:] }
        switch first.source {
        case .spotify:
            return SpotifyCLI.imageURLs(tracks.map { $0.id })
        case .neteaseMusic:
            return Dictionary(uniqueKeysWithValues: tracks.compactMap { track in
                track.artworkURL.map { (track.id, $0) }
            })
        case .appleMusic, .qqMusic:
            return [:]
        }
    }

    /// Cover URLs for playlist rows → id:url.
    static func coverURLs(forPlaylists playlists: [PlaylistRef]) -> [String: String] {
        guard let first = playlists.first else { return [:] }
        switch first.source {
        case .spotify:
            return SpotifyCLI.imageURLs(playlists.map { $0.id })
        case .neteaseMusic:
            return Dictionary(uniqueKeysWithValues: playlists.compactMap { playlist in
                playlist.coverURL.map { (playlist.id, $0) }
            })
        case .appleMusic, .qqMusic:
            return [:]
        }
    }

    static func setLiked(_ liked: Bool, for track: PlaylistTrackRef, in playlist: PlaylistRef?) {
        switch track.source {
        case .spotify:
            SpotifyCLI.setLiked(track.id, liked)
        case .appleMusic:
            if let playlist, let i = Int(track.id) {
                AppleMusicScript.setFavorite(index: i, inPlaylistID: playlist.id, liked)
            }
        case .qqMusic:
            break
        case .neteaseMusic:
            break
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
