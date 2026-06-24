import AppKit
import ApplicationServices

/// QQ音乐 has no scripting/CLI/now-playing API, but its native playback bar IS
/// exposed via Accessibility: one element's description encodes the song
/// ("歌曲名：X - 歌手名：Y"), the play button's description gives the play state,
/// and the menu bar "播放控制" offers pressable transport. So we read from the AX
/// tree and control through menu-bar AXPress. Requires Accessibility permission.
///
/// AX is still the source of truth for "what is currently selected/playing".
/// QQ's local PlayingList archive then enriches that AX snapshot with album art,
/// duration, and stable song ids.
final class QQMusicSource: NowPlayingSource {
    let kind: SourceKind = .qqMusic
    var canSetLiked: Bool { AXUI.isTrusted }

    private let bundleID = "com.tencent.QQMusicMac"
    private let metadataStore: QQMusicArchiveMetadataStore
    private let mediaRemote: MediaRemoteClientNowPlaying
    private let lock = NSLock()
    private var artID: String?
    private var art: NSImage?
    private var fetchingArt: String?
    private var progressTrackID: String?
    private var progressAnchorDate: Date?
    private var progressAnchorPosition: TimeInterval = 0
    private var lastPlaying = false

    init(
        metadataStore: QQMusicArchiveMetadataStore = .shared,
        mediaRemote: MediaRemoteClientNowPlaying = .shared
    ) {
        self.metadataStore = metadataStore
        self.mediaRemote = mediaRemote
    }

    var isRunning: Bool { AXUI.runningApp(bundleID) != nil }

    /// The "播放控制栏" group somewhere inside one of the app's windows.
    private func playbar() -> AXUIElement? {
        guard AXUI.requestTrustIfNeeded(), let app = AXUI.appElement(bundleID) else { return nil }
        for window in AXUI.windows(app) {
            if let bar = AXUI.firstDescendant(of: window, where: {
                AXUI.desc($0) == "播放控制栏" || AXUI.title($0) == "播放控制栏"
            }) {
                return bar
            }
        }
        return nil
    }

    private struct PlaybarSnapshot {
        var title: String
        var artist: String
        var liked: Bool?
        var playing: Bool?
    }

    private func snapshot() -> PlaybarSnapshot? {
        guard let bar = playbar() else { return nil }
        var title: String?
        var artist = ""
        var liked: Bool?
        var playing: Bool?
        for el in AXUI.children(bar) {
            guard let d = AXUI.desc(el) else { continue }
            if d.hasPrefix("歌曲名：") {
                let body = d.dropFirst("歌曲名：".count)
                if let r = body.range(of: " - 歌手名：") {
                    title = String(body[..<r.lowerBound])
                    artist = String(body[r.upperBound...])
                } else {
                    title = String(body)
                }
            } else if d.contains("取消喜欢") || d.contains("已喜欢") {
                liked = true
            } else if d.contains("添加到我喜欢") || d.contains("喜欢歌曲") || d == "喜欢" {
                liked = false
            } else if d == "暂停" || d.contains("暂停") {
                playing = true
            } else if d == "播放" {
                playing = false
            }
        }
        guard let title, !title.isEmpty else { return nil }
        return PlaybarSnapshot(title: title, artist: artist, liked: liked, playing: playing)
    }

    func currentTrack() -> Track? {
        let ax = snapshot()
        let mr = matchedMediaRemote(for: ax)
        guard ax != nil || mr != nil else { return nil }

        let title = ax?.title ?? mr?.title ?? ""
        let artist = ax?.artist ?? mr?.artist ?? ""
        let metadata = metadataStore.metadata(title: title, artist: artist)
        let id = metadata?.stableID ?? mr?.id ?? "qq:\(title)|\(artist)"
        let artworkFileURL = metadata?.artworkFileURL
        let mediaRemoteArtKey = mr?.artworkData.map { "qq-mediaremote:\(id):\($0.count):\($0.hashValue)" }

        lock.lock()
        let cachedArt = (artID == id) ? art : nil
        let artLoadKey = artworkFileURL.map { "qq-local:\($0.path)" } ?? mediaRemoteArtKey
        let needArt = artLoadKey != nil && artID != id && fetchingArt != id
        if needArt { fetchingArt = id }
        lock.unlock()

        if needArt, let artLoadKey {
            ArtworkCache.shared.image(key: artLoadKey, loader: {
                if let artworkFileURL, let image = NSImage(contentsOf: artworkFileURL) {
                    return image
                }
                guard let artworkData = mr?.artworkData else { return nil }
                return NSImage(data: artworkData)
            }) { [weak self] image in
                guard let self else { return }
                self.lock.lock()
                self.art = image
                self.artID = id
                self.fetchingArt = nil
                self.lock.unlock()
            }
        }

        return Track(
            id: id,
            title: title,
            artist: bestArtist(ax: artist, metadata: metadata, mediaRemote: mr),
            album: bestAlbum(metadata: metadata, mediaRemote: mr),
            duration: bestDuration(metadata: metadata, mediaRemote: mr),
            artwork: cachedArt,
            isLiked: ax?.liked,
            links: TrackLinks(
                track: metadata?.songMid.map { "https://y.qq.com/n/ryqq/songDetail/\($0)" },
                artist: nil,
                album: nil
            )
        )
    }

    func currentState() -> PlaybackState? {
        let ax = snapshot()
        let mr = matchedMediaRemote(for: ax, maxAge: 0, timeout: 0.8)
        guard ax != nil || mr != nil else { return nil }

        let title = ax?.title ?? mr?.title ?? ""
        let artist = ax?.artist ?? mr?.artist ?? ""
        let metadata = metadataStore.metadata(title: title, artist: artist)
        if let mr {
            let playing = ax?.playing ?? (mr.playbackRate > 0)
            let position = mr.estimatedPosition(forcePaused: !playing)
            writeDebug(
                snapshot: ax,
                mediaRemote: mr,
                path: "mediaRemote",
                position: position
            )
            return PlaybackState(
                isPlaying: playing,
                position: position,
                source: .qqMusic
            )
        }

        guard let snapshot = ax, let playing = snapshot.playing else { return nil }

        let id = metadata?.stableID ?? "qq:\(snapshot.title)|\(snapshot.artist)"
        let duration = metadata?.duration ?? 0

        lock.lock()
        let now = Date()
        if progressTrackID != id {
            progressTrackID = id
            progressAnchorDate = now
            progressAnchorPosition = 0
        } else if playing != lastPlaying {
            progressAnchorPosition = estimatedPosition(now: now, duration: duration)
            progressAnchorDate = now
        }
        lastPlaying = playing
        let position = estimatedPosition(now: now, duration: duration)
        lock.unlock()

        writeDebug(snapshot: snapshot, mediaRemote: mediaRemote.snapshot(bundleID: bundleID, maxAge: 0), path: "fallback", position: position)
        return PlaybackState(isPlaying: playing, position: position, source: .qqMusic)
    }

    private func estimatedPosition(now: Date, duration: TimeInterval) -> TimeInterval {
        guard lastPlaying, let progressAnchorDate else {
            return min(progressAnchorPosition, max(duration, 0))
        }
        let value = progressAnchorPosition + now.timeIntervalSince(progressAnchorDate)
        return duration > 0 ? min(value, duration) : value
    }

    private func matchedMediaRemote(
        for snapshot: PlaybarSnapshot?,
        maxAge: TimeInterval = 0.35,
        timeout: TimeInterval = 0.25
    ) -> MediaRemoteClientNowPlaying.Snapshot? {
        guard let mr = mediaRemote.snapshot(bundleID: bundleID, maxAge: maxAge, timeout: timeout) else {
            return nil
        }
        guard let snapshot else { return mr }
        guard mr.matches(title: snapshot.title, artist: snapshot.artist) else { return nil }
        return mr
    }

    private func bestArtist(
        ax: String,
        metadata: QQMusicMetadata?,
        mediaRemote: MediaRemoteClientNowPlaying.Snapshot?
    ) -> String {
        if let metadata, !metadata.artist.isEmpty { return metadata.artist }
        if let mediaRemote, !mediaRemote.artist.isEmpty { return mediaRemote.artist }
        return ax
    }

    private func bestAlbum(
        metadata: QQMusicMetadata?,
        mediaRemote: MediaRemoteClientNowPlaying.Snapshot?
    ) -> String {
        if let metadata, !metadata.album.isEmpty { return metadata.album }
        return mediaRemote?.album ?? ""
    }

    private func bestDuration(
        metadata: QQMusicMetadata?,
        mediaRemote: MediaRemoteClientNowPlaying.Snapshot?
    ) -> TimeInterval {
        if let duration = metadata?.duration, duration > 0 { return duration }
        return mediaRemote?.duration ?? 0
    }

    private func writeDebug(
        snapshot: PlaybarSnapshot?,
        mediaRemote: MediaRemoteClientNowPlaying.Snapshot?,
        path: String,
        position: TimeInterval
    ) {
        let flag = URL(fileURLWithPath: "/tmp/misland-debug-on")
        guard FileManager.default.fileExists(atPath: flag.path) else { return }
        let lines = [
            "time=\(Date())",
            "path=\(path)",
            "axTitle=\(snapshot?.title ?? "nil")",
            "axArtist=\(snapshot?.artist ?? "nil")",
            "axPlaying=\(snapshot?.playing.map(String.init) ?? "nil")",
            "mrTitle=\(mediaRemote?.title ?? "nil")",
            "mrArtist=\(mediaRemote?.artist ?? "nil")",
            "mrElapsed=\(mediaRemote.map { String(format: "%.3f", $0.elapsed) } ?? "nil")",
            "mrDuration=\(mediaRemote.map { String(format: "%.3f", $0.duration) } ?? "nil")",
            "mrRate=\(mediaRemote.map { String(format: "%.3f", $0.playbackRate) } ?? "nil")",
            "mrTimestamp=\(mediaRemote?.timestamp.map(String.init) ?? "nil")",
            "mrMatches=\(snapshot.flatMap { mediaRemote?.matches(title: $0.title, artist: $0.artist).description } ?? "nil")",
            "position=\(String(format: "%.3f", position))",
        ]
        try? (lines.joined(separator: "\n") + "\n").write(
            to: URL(fileURLWithPath: "/tmp/misland-qq-debug.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: Control — via the "播放控制" menu (items are AXPress-able)

    private func app() -> AXUIElement? { AXUI.appElement(bundleID) }

    func playPause() {
        guard AXUI.requestTrustIfNeeded(), let app = app() else { return }
        AXUI.pressMenuItem(app, menu: "播放控制", titleIn: ["暂停", "播放"])
    }

    func pause() {
        guard AXUI.requestTrustIfNeeded(), let app = app() else { return }
        // Only the "暂停" item exists while playing, so this is a no-op when paused.
        AXUI.pressMenuItem(app, menu: "播放控制", titleIn: ["暂停"])
    }

    func next() {
        guard AXUI.requestTrustIfNeeded(), let app = app() else { return }
        AXUI.pressMenuItem(app, menu: "播放控制", titleIn: ["下一首"])
    }

    func previous() {
        guard AXUI.requestTrustIfNeeded(), let app = app() else { return }
        AXUI.pressMenuItem(app, menu: "播放控制", titleIn: ["上一首"])
    }

    func seek(to position: TimeInterval) {
        guard let snapshot = snapshot(),
              let mr = matchedMediaRemote(for: snapshot, maxAge: 0, timeout: 0.8) else {
            return
        }
        let metadata = metadataStore.metadata(title: snapshot.title, artist: snapshot.artist)
        let duration = bestDuration(metadata: metadata, mediaRemote: mr)
        lock.lock()
        progressTrackID = metadata?.stableID ?? "qq:\(snapshot.title)|\(snapshot.artist)"
        progressAnchorDate = Date()
        progressAnchorPosition = duration > 0 ? min(max(position, 0), duration) : max(position, 0)
        lock.unlock()
        MediaRemoteAdapterBridge.shared.seek(to: position, expectedBundleID: bundleID)
    }

    func setLiked(_ liked: Bool) {
        guard AXUI.requestTrustIfNeeded(), let app = app() else { return }
        // One toggle item, titled for its action ("喜欢歌曲" to like / "取消喜欢" to unlike).
        AXUI.pressMenuItem(app, menu: "播放控制",
                           titleIn: liked ? ["添加到我喜欢", "喜欢歌曲"] : ["取消喜欢"])
    }
}
