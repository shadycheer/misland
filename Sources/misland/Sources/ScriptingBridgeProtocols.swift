import ScriptingBridge
import AppKit

@objc enum SBPlayerState: Int {
    case stopped = 0x6b505353 // 'kPSS'
    case playing = 0x6b505350 // 'kPSP'
    case paused  = 0x6b505370 // 'kPSp'
}

// Spotify
@objc protocol SpotifyTrack {
    @objc optional var id: String { get }       // spotify uri
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var duration: Int { get }    // milliseconds
    @objc optional var artworkUrl: String { get }
}

@objc protocol SpotifyApplication {
    @objc optional var currentTrack: SpotifyTrack { get }
    @objc optional var playerState: SBPlayerState { get }
    @objc optional var playerPosition: Double { get } // seconds
    @objc optional var isRunning: Bool { get }        // cheap: SB target state
    @objc optional func playpause()
    @objc optional func pause()
    @objc optional func nextTrack()
    @objc optional func previousTrack()
}

// Apple Music (Music.app)
@objc protocol MusicArtwork {
    @objc optional var data: NSImage { get }
}

@objc protocol MusicTrack {
    @objc optional var id: Int { get }
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var duration: Double { get } // seconds
    @objc optional var favorited: Bool { get }   // renamed from 'loved' in recent Music
    @objc optional var artworks: [MusicArtwork] { get }
}

@objc protocol MusicApplication {
    @objc optional var currentTrack: MusicTrack { get }
    @objc optional var playerState: SBPlayerState { get }
    @objc optional var playerPosition: Double { get }
    @objc optional var isRunning: Bool { get }        // cheap: SB target state
    @objc optional func playpause()
    @objc optional func pause()
    @objc optional func nextTrack()
    @objc optional func previousTrack()
}

extension SBApplication: SpotifyApplication, MusicApplication {}
