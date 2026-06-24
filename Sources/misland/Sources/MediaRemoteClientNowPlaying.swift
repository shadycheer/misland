import AppKit
import Foundation
import ObjectiveC

/// Per-application reader for macOS' private MediaRemote now-playing state.
/// It asks the system for a specific MRClient by bundle id, avoiding the global
/// "current media app" collision between Spotify, Music, QQ Music, and NetEase.
final class MediaRemoteClientNowPlaying {
    static let shared = MediaRemoteClientNowPlaying()

    struct Snapshot {
        let bundleID: String
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let elapsed: TimeInterval
        let playbackRate: Double
        let timestamp: Date?
        let artworkData: Data?

        var id: String {
            "\(bundleID):\(title)|\(artist)|\(album)|\(Int(duration.rounded()))"
        }

        func matches(title axTitle: String, artist axArtist: String) -> Bool {
            guard normalize(title) == normalize(axTitle) else { return false }
            if axArtist.isEmpty { return true }
            let left = normalize(artist)
            let right = normalize(axArtist)
            return left == right || left.contains(right) || right.contains(left)
        }

        func estimatedPosition(now: Date = Date(), forcePaused: Bool = false) -> TimeInterval {
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

    private typealias ClientsBlock = @convention(block) (CFArray?) -> Void
    private typealias GetClients = @convention(c) (DispatchQueue, ClientsBlock) -> Void
    private typealias InfoBlock = @convention(block) (CFDictionary?) -> Void
    private typealias ObjCMsgClass0 = @convention(c) (AnyClass, Selector) -> AnyObject?
    private typealias ObjCMsgObj0 = @convention(c) (AnyObject, Selector) -> AnyObject?
    private typealias ObjCMsgObj1 = @convention(c) (AnyObject, Selector, AnyObject?) -> AnyObject?
    private typealias ObjCMsgVoid1 = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    private typealias ObjCMsgVoidQueueBlock = @convention(c) (AnyObject, Selector, DispatchQueue, InfoBlock) -> Void
    private typealias ObjCMsgString0 = @convention(c) (AnyObject, Selector) -> AnyObject?

    private let lock = NSLock()
    private var cachedAt: [String: Date] = [:]
    private var cached: [String: Snapshot] = [:]
    private let getClients: GetClients?
    private let msgClass0: ObjCMsgClass0?
    private let msgObj0: ObjCMsgObj0?
    private let msgObj1: ObjCMsgObj1?
    private let msgVoid1: ObjCMsgVoid1?
    private let msgVoidQueueBlock: ObjCMsgVoidQueueBlock?
    private let msgString0: ObjCMsgString0?

    private init() {
        let mediaRemotePath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        let mrHandle = dlopen(mediaRemotePath, RTLD_NOW)
        getClients = mrHandle.flatMap { dlsym($0, "MRMediaRemoteGetNowPlayingClients") }.map {
            unsafeBitCast($0, to: GetClients.self)
        }

        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        let objcSend = defaultHandle.flatMap { dlsym($0, "objc_msgSend") }
        msgClass0 = objcSend.map { unsafeBitCast($0, to: ObjCMsgClass0.self) }
        msgObj0 = objcSend.map { unsafeBitCast($0, to: ObjCMsgObj0.self) }
        msgObj1 = objcSend.map { unsafeBitCast($0, to: ObjCMsgObj1.self) }
        msgVoid1 = objcSend.map { unsafeBitCast($0, to: ObjCMsgVoid1.self) }
        msgVoidQueueBlock = objcSend.map { unsafeBitCast($0, to: ObjCMsgVoidQueueBlock.self) }
        msgString0 = objcSend.map { unsafeBitCast($0, to: ObjCMsgString0.self) }
    }

    func snapshot(
        bundleID: String,
        maxAge: TimeInterval = 0.35,
        timeout: TimeInterval = 0.35
    ) -> Snapshot? {
        let now = Date()
        lock.lock()
        if let at = cachedAt[bundleID], now.timeIntervalSince(at) <= maxAge {
            let value = cached[bundleID]
            lock.unlock()
            return value
        }
        lock.unlock()

        guard let client = client(bundleID: bundleID, timeout: timeout),
              let playerPath = playerPath(client: client),
              let request = request(playerPath: playerPath),
              let msgVoidQueueBlock else {
            return adapterSnapshot(bundleID: bundleID)
        }

        let sem = DispatchSemaphore(value: 0)
        var result: Snapshot?
        let block: InfoBlock = { dict in
            result = Self.parse(dict, bundleID: bundleID)
            sem.signal()
        }
        msgVoidQueueBlock(
            request,
            Selector(("requestNowPlayingInfoOnQueue:completion:")),
            DispatchQueue.global(qos: .userInitiated),
            block
        )
        guard sem.wait(timeout: .now() + timeout) == .success else {
            return adapterSnapshot(bundleID: bundleID)
        }
        if result == nil {
            result = adapterSnapshot(bundleID: bundleID)
        }

        lock.lock()
        cachedAt[bundleID] = now
        cached[bundleID] = result
        lock.unlock()
        return result
    }

    private func adapterSnapshot(bundleID: String) -> Snapshot? {
        MediaRemoteAdapterBridge.shared.snapshot(bundleID: bundleID)
    }

    private func client(bundleID: String, timeout: TimeInterval) -> AnyObject? {
        guard let getClients else { return nil }
        let sem = DispatchSemaphore(value: 0)
        var result: AnyObject?
        let block: ClientsBlock = { [weak self] array in
            guard let self, let array = array as? [AnyObject] else {
                sem.signal()
                return
            }
            result = array.first { self.bundleID(of: $0) == bundleID }
            sem.signal()
        }
        getClients(.global(qos: .userInitiated), block)
        guard sem.wait(timeout: .now() + timeout) == .success else { return nil }
        return result
    }

    private func bundleID(of client: AnyObject) -> String? {
        msgString0?(client, Selector(("bundleIdentifier"))) as? String
    }

    private func playerPath(client: AnyObject) -> AnyObject? {
        guard let originClass = NSClassFromString("MROrigin"),
              let pathClass = NSClassFromString("MRPlayerPath"),
              let msgClass0,
              let msgObj0,
              let msgVoid1,
              let origin = msgClass0(originClass, Selector(("localOrigin"))),
              let allocated = msgClass0(pathClass, Selector(("alloc"))),
              let path = msgObj0(allocated, Selector(("init"))) else {
            return nil
        }
        msgVoid1(path, Selector(("setOrigin:")), origin)
        msgVoid1(path, Selector(("setClient:")), client)
        return path
    }

    private func request(playerPath: AnyObject) -> AnyObject? {
        guard let requestClass = NSClassFromString("MRNowPlayingRequest"),
              let msgClass0,
              let msgObj1,
              let allocated = msgClass0(requestClass, Selector(("alloc"))) else {
            return nil
        }
        return msgObj1(allocated, Selector(("initWithPlayerPath:")), playerPath)
    }

    private static func parse(_ dict: CFDictionary?, bundleID: String) -> Snapshot? {
        guard let dict = dict as? [String: Any],
              let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
              !title.isEmpty else {
            return nil
        }
        return Snapshot(
            bundleID: bundleID,
            title: title,
            artist: dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
            album: dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
            duration: double(dict["kMRMediaRemoteNowPlayingInfoDuration"]),
            elapsed: double(dict["kMRMediaRemoteNowPlayingInfoElapsedTime"]),
            playbackRate: double(dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"]),
            timestamp: dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date,
            artworkData: dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        )
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
