import AppKit

final class NetEaseMusicSource: NowPlayingSource {
    let kind: SourceKind = .neteaseMusic
    let canSetLiked = false

    private let bundleID = "com.netease.163music"
    private let mediaRemote: MediaRemoteClientNowPlaying
    private let libraryStore: NetEaseMusicLibraryStore
    private let lock = NSLock()
    private var artID: String?
    private var art: NSImage?
    private var fetchingArt: String?
    private var lastSnapshot: MediaRemoteClientNowPlaying.Snapshot?
    private var lastSnapshotAt: Date?

    init(
        mediaRemote: MediaRemoteClientNowPlaying = .shared,
        libraryStore: NetEaseMusicLibraryStore = .shared
    ) {
        self.mediaRemote = mediaRemote
        self.libraryStore = libraryStore
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    func currentTrack() -> Track? {
        guard let mr = snapshot(maxAge: 0.35, allowRecent: true) else { return nil }
        let local = libraryStore.metadata(title: mr.title, artist: mr.artist, album: mr.album)
        let id = local?.stableID ?? mr.id
        let artURL = local?.artworkURL
        let mediaRemoteArtKey = mr.artworkData.map { "netease-mediaremote:\(id):\($0.count):\($0.hashValue)" }
        let artKey = artURL.map { "netease-url:\($0)" } ?? mediaRemoteArtKey

        lock.lock()
        let cachedArt = (artID == id) ? art : nil
        let needArt = artKey != nil && artID != id && fetchingArt != id
        if needArt { fetchingArt = id }
        lock.unlock()

        if needArt, let artKey {
            ArtworkCache.shared.image(key: artKey, loader: {
                if let artURL, let url = URL(string: artURL),
                   let data = try? Data(contentsOf: url),
                   let image = NSImage(data: data) {
                    return image
                }
                guard let data = mr.artworkData else { return nil }
                return NSImage(data: data)
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
            title: local?.title ?? mr.title,
            artist: local?.artist ?? mr.artist,
            album: local?.album ?? mr.album,
            duration: local?.duration ?? mr.duration,
            artwork: cachedArt,
            isLiked: local.map { libraryStore.isLiked(trackID: $0.id) },
            links: local.map { TrackLinks(track: $0.songURL) }
        )
    }

    func currentState() -> PlaybackState? {
        guard let mr = snapshot(maxAge: 0, allowRecent: true) else { return nil }
        return PlaybackState(
            isPlaying: mr.playbackRate > 0,
            position: mr.estimatedPosition(),
            source: .neteaseMusic
        )
    }

    private func snapshot(
        maxAge: TimeInterval,
        allowRecent: Bool
    ) -> MediaRemoteClientNowPlaying.Snapshot? {
        if let live = mediaRemote.snapshot(bundleID: bundleID, maxAge: maxAge) {
            lock.lock()
            lastSnapshot = live
            lastSnapshotAt = Date()
            lock.unlock()
            return live
        }
        guard allowRecent else { return nil }
        lock.lock()
        let recent = lastSnapshot
        let recentAt = lastSnapshotAt
        lock.unlock()
        guard let recent, let recentAt, Date().timeIntervalSince(recentAt) <= 3 else {
            return nil
        }
        return recent
    }

    func playPause() {
        if !pressMenuOrButton(menus: ["播放控制", "播放", "控制"], labels: ["播放/暂停", "暂停/播放", "暂停", "播放"]) {
            MediaRemoteAdapterBridge.shared.send(command: 2, expectedBundleID: bundleID)
        }
    }

    func pause() {
        if !pressMenuOrButton(menus: ["播放控制", "播放", "控制"], labels: ["暂停"]) {
            MediaRemoteAdapterBridge.shared.send(command: 1, expectedBundleID: bundleID)
        }
    }

    func next() {
        if !pressMenuOrButton(menus: ["播放控制", "播放", "控制"], labels: ["下一首", "下一曲"]) {
            MediaRemoteAdapterBridge.shared.send(command: 4, expectedBundleID: bundleID)
        }
    }

    func previous() {
        if !pressMenuOrButton(menus: ["播放控制", "播放", "控制"], labels: ["上一首", "上一曲"]) {
            MediaRemoteAdapterBridge.shared.send(command: 5, expectedBundleID: bundleID)
        }
    }

    func seek(to position: TimeInterval) {
        let ok = MediaRemoteAdapterBridge.shared.seek(to: position, expectedBundleID: bundleID)
        guard ok else { return }
        lock.lock()
        if let old = lastSnapshot {
            let clamped = old.duration > 0 ? min(max(position, 0), old.duration) : max(position, 0)
            lastSnapshot = MediaRemoteClientNowPlaying.Snapshot(
                bundleID: old.bundleID,
                title: old.title,
                artist: old.artist,
                album: old.album,
                duration: old.duration,
                elapsed: clamped,
                playbackRate: old.playbackRate,
                timestamp: Date(),
                artworkData: old.artworkData
            )
            lastSnapshotAt = Date()
        }
        lock.unlock()
    }

    func setLiked(_ liked: Bool) {}

    private func pressMenuOrButton(menus: [String], labels: [String]) -> Bool {
        guard AXUI.requestTrustIfNeeded(), let app = AXUI.appElement(bundleID) else { return false }
        if AXUI.pressAnyMenuItem(app, menus: menus, titleIn: labels) { return true }
        return AXUI.pressFirstDescendant(in: app, labels: labels)
    }
}
