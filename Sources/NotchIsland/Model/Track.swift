import AppKit

enum SourceKind: String, Equatable {
    case spotify
    case appleMusic
}

struct Track: Equatable {
    let id: String          // stable per-track id (player track id or url)
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    var artwork: NSImage?
    var isLiked: Bool?      // nil = source can't report/like

    static func == (l: Track, r: Track) -> Bool {
        l.id == r.id && l.title == r.title && l.artist == r.artist
            && l.album == r.album && l.duration == r.duration
            && l.isLiked == r.isLiked
    }
}

struct PlaybackState: Equatable {
    var isPlaying: Bool
    var position: TimeInterval
    var source: SourceKind
}
