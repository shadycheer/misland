import Foundation

struct NetEasePlaylistMetadata: Equatable {
    let id: Int64
    let name: String
    let coverURL: String?
    let specialType: Int?
    let trackCount: Int
}

struct NetEaseTrackMetadata: Equatable {
    let id: Int64
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artworkURL: String?

    var stableID: String { "netease:\(id)" }
    var songURL: String { "https://music.163.com/#/song?id=\(id)" }
}

final class NetEaseMusicLibraryStore {
    static let shared = NetEaseMusicLibraryStore()

    private struct PlaylistRow: Decodable {
        let pid: Int64
        let playlist: String
        let cachedTrackCount: Int?
    }

    private struct TrackRow: Decodable {
        let tid: Int64
        let track: String
    }

    private struct JSONTrackRow: Decodable {
        let id: String
        let jsonStr: String
    }

    private struct IDRow: Decodable {
        let tid: Int64
    }

    private struct NetEasePlaylistJSON: Decodable {
        let id: Int64?
        let name: String?
        let coverImgUrl: String?
        let specialType: Int?
        let trackCount: Int?
    }

    private struct NetEaseTrackJSON: Decodable {
        struct Artist: Decodable { let name: String? }
        struct Album: Decodable {
            let name: String?
            let picUrl: String?
        }

        let id: FlexibleInt64?
        let name: String?
        let duration: FlexibleDouble?
        let artists: [Artist]?
        let ar: [Artist]?
        let album: Album?
        let al: Album?
    }

    private struct FlexibleInt64: Decodable {
        let value: Int64

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int64.self) {
                value = i
            } else if let s = try? c.decode(String.self), let i = Int64(s) {
                value = i
            } else {
                throw DecodingError.typeMismatch(Int64.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected Int64 or String"))
            }
        }
    }

    private struct FlexibleDouble: Decodable {
        let value: Double

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) {
                value = d
            } else if let s = try? c.decode(String.self), let d = Double(s) {
                value = d
            } else {
                throw DecodingError.typeMismatch(Double.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected Double or String"))
            }
        }
    }

    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private var cachedMTime: Date?
    private var cachedPlaylists: [NetEasePlaylistMetadata] = []
    private var cachedTracksByPlaylist: [Int64: [NetEaseTrackMetadata]] = [:]
    private var cachedAllTracks: [NetEaseTrackMetadata] = []
    private var cachedLikedIDs: Set<Int64> = []

    private var dbURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.netease.163music/Data/Documents/storage/sqlite_storage.sqlite3")
    }

    func playlists() -> [NetEasePlaylistMetadata] {
        refreshIfNeeded()
        lock.lock()
        let result = cachedPlaylists
        lock.unlock()
        return result
    }

    func tracks(playlistID: Int64) -> [NetEaseTrackMetadata] {
        refreshIfNeeded()
        lock.lock()
        if let cached = cachedTracksByPlaylist[playlistID] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let sql = """
        select t.tid, t.track
        from web_playlist_track pt
        join web_track t on t.tid = pt.tid
        where pt.pid = \(playlistID)
        order by pt."order";
        """
        let parsed = sqliteJSON(TrackRow.self, sql: sql).compactMap(parseTrack)

        lock.lock()
        cachedTracksByPlaylist[playlistID] = parsed
        lock.unlock()
        return parsed
    }

    func metadata(title: String, artist: String, album: String) -> NetEaseTrackMetadata? {
        let targetTitle = normalized(title)
        let targetArtist = normalized(artist)
        let targetAlbum = normalized(album)
        guard !targetTitle.isEmpty else { return nil }

        let tracks = allTracks()
        return tracks.first { item in
            normalized(item.title) == targetTitle
                && (targetArtist.isEmpty || normalized(item.artist).contains(targetArtist) || targetArtist.contains(normalized(item.artist)))
        } ?? tracks.first { item in
            normalized(item.title) == targetTitle
                && (targetAlbum.isEmpty || normalized(item.album) == targetAlbum)
        } ?? tracks.first { normalized($0.title) == targetTitle }
    }

    func likedTrackIDs() -> Set<Int64> {
        refreshIfNeeded()
        lock.lock()
        let result = cachedLikedIDs
        lock.unlock()
        return result
    }

    func isLiked(trackID: Int64) -> Bool {
        likedTrackIDs().contains(trackID)
    }

    private func allTracks() -> [NetEaseTrackMetadata] {
        refreshIfNeeded()
        lock.lock()
        if !cachedAllTracks.isEmpty {
            let result = cachedAllTracks
            lock.unlock()
            return result
        }
        lock.unlock()

        let rows = sqliteJSON(TrackRow.self, sql: "select tid, track from web_track;")
        var seen = Set<Int64>()
        let webTracks = rows.compactMap(parseTrack)
        let recentTracks = sqliteJSON(JSONTrackRow.self, sql: """
        select id, jsonStr from historyTracks
        union all
        select id, jsonStr from dbTrack;
        """).compactMap(parseJSONTrack)
        let parsed = (recentTracks + webTracks).filter { seen.insert($0.id).inserted }

        lock.lock()
        cachedAllTracks = parsed
        lock.unlock()
        return parsed
    }

    private func refreshIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
              let mtime = attrs[.modificationDate] as? Date else {
            return
        }

        lock.lock()
        if cachedMTime == mtime {
            lock.unlock()
            return
        }
        lock.unlock()

        let playlistRows = sqliteJSON(PlaylistRow.self, sql: """
        select p.pid,
               p.playlist,
               count(pt.tid) as cachedTrackCount
        from web_playlist p
        left join web_playlist_track pt on pt.pid = p.pid
        group by p.pid;
        """)
        let playlists = playlistRows.compactMap(parsePlaylist).filter { $0.trackCount > 0 }.sorted {
            if $0.specialType == 5 { return true }
            if $1.specialType == 5 { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        let likedPlaylistID = playlists.first { $0.specialType == 5 }?.id
        let likedIDs = likedPlaylistID.map { id in
            Set(sqliteJSON(IDRow.self, sql: "select tid from web_playlist_track where pid = \(id);").map(\.tid))
        } ?? []

        lock.lock()
        cachedMTime = mtime
        cachedPlaylists = playlists
        cachedTracksByPlaylist = [:]
        cachedAllTracks = []
        cachedLikedIDs = likedIDs
        lock.unlock()
    }

    private func parsePlaylist(_ row: PlaylistRow) -> NetEasePlaylistMetadata? {
        guard let data = row.playlist.data(using: .utf8),
              let json = try? decoder.decode(NetEasePlaylistJSON.self, from: data),
              let name = json.name,
              !name.isEmpty else {
            return nil
        }
        return NetEasePlaylistMetadata(
            id: json.id ?? row.pid,
            name: name,
            coverURL: json.coverImgUrl,
            specialType: json.specialType,
            trackCount: row.cachedTrackCount ?? json.trackCount ?? 0
        )
    }

    private func parseTrack(_ row: TrackRow) -> NetEaseTrackMetadata? {
        parseTrackJSON(row.track, fallbackID: row.tid)
    }

    private func parseJSONTrack(_ row: JSONTrackRow) -> NetEaseTrackMetadata? {
        parseTrackJSON(row.jsonStr, fallbackID: Int64(row.id) ?? 0)
    }

    private func parseTrackJSON(_ raw: String, fallbackID: Int64) -> NetEaseTrackMetadata? {
        guard let data = raw.data(using: .utf8),
              let json = try? decoder.decode(NetEaseTrackJSON.self, from: data),
              let title = json.name,
              !title.isEmpty else {
            return nil
        }
        let artists = (json.artists ?? json.ar ?? []).compactMap(\.name).filter { !$0.isEmpty }
        let album = json.album ?? json.al
        let durationValue = json.duration?.value ?? 0
        return NetEaseTrackMetadata(
            id: json.id?.value ?? fallbackID,
            title: title,
            artist: artists.joined(separator: "/"),
            album: album?.name ?? "",
            duration: durationValue > 10_000 ? durationValue / 1000 : durationValue,
            artworkURL: album?.picUrl.map(highResolutionArtworkURL)
        )
    }

    private func highResolutionArtworkURL(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else { return urlString }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "param" }
        items.append(URLQueryItem(name: "param", value: "1200y1200"))
        components.queryItems = items
        return components.url?.absoluteString ?? urlString
    }

    private func sqliteJSON<T: Decodable>(_ type: T.Type, sql: String) -> [T] {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return [] }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = ["-json", "-batch", dbURL.path, sql]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return [] }
        return (try? decoder.decode([T].self, from: data)) ?? []
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\s　]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
