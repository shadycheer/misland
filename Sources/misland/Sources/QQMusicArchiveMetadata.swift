import AppKit
import Foundation

struct QQMusicMetadata: Equatable {
    let songID: Int64?
    let songMid: String?
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artworkURL: String?

    var stableID: String {
        if let songMid, !songMid.isEmpty { return "qq:\(songMid)" }
        if let songID { return "qq:\(songID)" }
        return "qq:\(title)|\(artist)"
    }
}

/// Reads QQ Music's local NSKeyedArchiver playlist cache. The current sqlite DB
/// can be empty while this archive still contains the active playlist metadata.
final class QQMusicArchiveMetadataStore {
    static let shared = QQMusicArchiveMetadataStore()

    private let lock = NSLock()
    private var cachedMTime: Date?
    private var cached: [QQMusicMetadata] = []

    private var archiveURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.tencent.QQMusicMac/Data/Library/Application Support/QQMusicMac/iTemp/PlayingList.archive")
    }

    func metadata(title: String, artist: String) -> QQMusicMetadata? {
        load().first { item in
            item.title == title && (artist.isEmpty || item.artist == artist || item.artist.contains(artist))
        } ?? load().first { $0.title == title }
    }

    private func load() -> [QQMusicMetadata] {
        let url = archiveURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date else {
            return []
        }

        lock.lock()
        if cachedMTime == mtime {
            let result = cached
            lock.unlock()
            return result
        }
        lock.unlock()

        let parsed = (try? parseArchive(at: url)) ?? []

        lock.lock()
        cachedMTime = mtime
        cached = parsed
        lock.unlock()
        return parsed
    }

    private func parseArchive(at url: URL) throws -> [QQMusicMetadata] {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any] else {
            return []
        }

        var songs: [QQMusicMetadata] = []
        for object in objects {
            guard let dict = object as? [String: Any],
                  dict["songName"] != nil,
                  let title = string(dict["songName"], in: objects),
                  !title.isEmpty else { continue }

            let singer = dictionary(dict["singerInfo"], in: objects)
            let album = dictionary(dict["albumInfo"], in: objects)
            let artist = singer.flatMap { string($0["name"], in: objects) } ?? ""
            let albumName = album.flatMap { string($0["name"], in: objects) } ?? ""
            songs.append(QQMusicMetadata(
                songID: int64(dict["songId"], in: objects),
                songMid: string(dict["song_Mid"], in: objects),
                title: title,
                artist: artist,
                album: albumName,
                duration: TimeInterval(int64(dict["song_Duration"], in: objects) ?? 0),
                artworkURL: nil
            ))
        }
        return songs
    }

    private func dictionary(_ value: Any?, in objects: [Any]) -> [String: Any]? {
        guard let index = uid(value), objects.indices.contains(index) else { return nil }
        return objects[index] as? [String: Any]
    }

    private func string(_ value: Any?, in objects: [Any]) -> String? {
        if let s = value as? String { return s }
        guard let index = uid(value), objects.indices.contains(index) else { return nil }
        return objects[index] as? String
    }

    private func int64(_ value: Any?, in objects: [Any]) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        guard let index = uid(value), objects.indices.contains(index) else { return nil }
        return (objects[index] as? NSNumber)?.int64Value
    }

    private func uid(_ value: Any?) -> Int? {
        guard let value else { return nil }
        let text = String(describing: value)
        guard let range = text.range(of: #"value = \d+"#, options: .regularExpression) else {
            return nil
        }
        return Int(text[range].replacingOccurrences(of: "value = ", with: ""))
    }

}
