import AppKit
import Foundation

/// Thin, isolated reader for macOS' private MediaRemote now-playing snapshot.
/// This is local system state: no auth, no network, no QQ process memory reads.
final class QQMusicMediaRemoteNowPlaying {
    static let shared = QQMusicMediaRemoteNowPlaying()

    struct Snapshot {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let elapsed: TimeInterval
        let playbackRate: Double
        let timestamp: Date?
        let artworkData: Data?

        func matches(title axTitle: String, artist axArtist: String) -> Bool {
            guard normalize(title) == normalize(axTitle) else { return false }
            if axArtist.isEmpty { return true }
            let left = normalize(artist)
            let right = normalize(axArtist)
            return left == right || left.contains(right) || right.contains(left)
        }

        func estimatedPosition(now: Date = Date(), forcePaused: Bool) -> TimeInterval {
            var value = elapsed
            if !forcePaused, playbackRate > 0, let timestamp {
                value += now.timeIntervalSince(timestamp) * playbackRate
            }
            if duration > 0 {
                value = min(value, duration)
            }
            return max(0, value)
        }
    }

    private typealias MRNowPlayingBlock = @convention(block) (CFDictionary?) -> Void
    private typealias MRGetNowPlayingInfo = @convention(c) (DispatchQueue, MRNowPlayingBlock) -> Void
    private typealias MRSetElapsedTime = @convention(c) (Double) -> Void

    private let lock = NSLock()
    private var cachedAt: Date?
    private var cached: Snapshot?
    private let getInfo: MRGetNowPlayingInfo?
    private let setElapsedTime: MRSetElapsedTime?

    private init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else {
            getInfo = nil
            setElapsedTime = nil
            return
        }
        getInfo = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo").map {
            unsafeBitCast($0, to: MRGetNowPlayingInfo.self)
        }
        setElapsedTime = dlsym(handle, "MRMediaRemoteSetElapsedTime").map {
            unsafeBitCast($0, to: MRSetElapsedTime.self)
        }
    }

    func snapshot(maxAge: TimeInterval = 0.35, timeout: TimeInterval = 0.25) -> Snapshot? {
        let now = Date()
        lock.lock()
        if let cachedAt, now.timeIntervalSince(cachedAt) <= maxAge {
            let result = cached
            lock.unlock()
            return result
        }
        lock.unlock()

        guard let getInfo else { return nil }
        let sem = DispatchSemaphore(value: 0)
        var result: Snapshot?
        let block: MRNowPlayingBlock = { dict in
            result = Self.parse(dict)
            sem.signal()
        }
        getInfo(.global(qos: .userInitiated), block)
        guard sem.wait(timeout: .now() + timeout) == .success else { return nil }

        lock.lock()
        cachedAt = now
        cached = result
        lock.unlock()
        return result
    }

    func seek(to position: TimeInterval, duration: TimeInterval) -> Bool {
        guard let setElapsedTime else { return false }
        let clamped = duration > 0 ? min(max(position, 0), duration) : max(position, 0)
        setElapsedTime(clamped)

        lock.lock()
        if let old = cached {
            cached = Snapshot(
                title: old.title,
                artist: old.artist,
                album: old.album,
                duration: old.duration,
                elapsed: clamped,
                playbackRate: old.playbackRate,
                timestamp: Date(),
                artworkData: old.artworkData
            )
            cachedAt = Date()
        }
        lock.unlock()
        return true
    }

    private static func parse(_ dict: CFDictionary?) -> Snapshot? {
        guard let dict = dict as? [String: Any],
              let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
              !title.isEmpty else {
            return nil
        }
        return Snapshot(
            title: title,
            artist: dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
            album: dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
            duration: time(dict["kMRMediaRemoteNowPlayingInfoDuration"]),
            elapsed: time(dict["kMRMediaRemoteNowPlayingInfoElapsedTime"]),
            playbackRate: double(dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"]),
            timestamp: dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date,
            artworkData: dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        )
    }

    private static func time(_ value: Any?) -> TimeInterval {
        double(value)
    }

    private static func double(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return 0
    }
}

private func normalize(_ value: String) -> String {
    value
        .replacingOccurrences(of: "（", with: "(")
        .replacingOccurrences(of: "）", with: ")")
        .replacingOccurrences(of: " ", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}
