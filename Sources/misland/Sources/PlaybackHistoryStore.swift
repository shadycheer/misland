import AppKit
import Foundation

struct PlaybackHistoryEntry: Identifiable, Equatable, Codable {
    let id: String
    let source: SourceKind
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let playedAt: Date
    let trackLink: String?
    let artworkPath: String?

    var canReplay: Bool {
        switch source {
        case .spotify, .appleMusic:
            return true
        case .qqMusic, .neteaseMusic:
            return false
        }
    }
}

final class PlaybackHistoryStore {
    static let shared = PlaybackHistoryStore()

    private let lock = NSLock()
    private let key = "playbackHistory.v1"
    private let limit = 80
    private var cached: [PlaybackHistoryEntry]?

    func record(track: Track, source: SourceKind) {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let now = Date()
        let id = "\(source.rawValue):\(track.id)"
        let artworkPath = saveArtwork(track.artwork, id: id)
        let entry = PlaybackHistoryEntry(
            id: id,
            source: source,
            trackID: track.id,
            title: title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            playedAt: now,
            trackLink: track.links?.track,
            artworkPath: artworkPath
        )

        lock.lock()
        var items = loadLocked()
        if let first = items.first, first.id == entry.id {
            let updated = merge(existing: first, incoming: entry)
            if updated != first {
                items[0] = updated
                cached = items
                saveLocked(items)
            }
            lock.unlock()
            return
        }
        if let oldIndex = items.firstIndex(where: { $0.id == entry.id }) {
            let old = items.remove(at: oldIndex)
            items.insert(merge(existing: old, incoming: entry), at: 0)
        } else {
            items.insert(entry, at: 0)
        }
        if items.count > limit { items = Array(items.prefix(limit)) }
        cached = items
        saveLocked(items)
        lock.unlock()
    }

    func entries() -> [PlaybackHistoryEntry] {
        lock.lock()
        let result = loadLocked()
        lock.unlock()
        return result
    }

    func clear() {
        lock.lock()
        cached = []
        UserDefaults.standard.removeObject(forKey: key)
        lock.unlock()
    }

    func replay(_ entry: PlaybackHistoryEntry) {
        switch entry.source {
        case .spotify:
            SpotifyCLI.play(uri: entry.trackLink ?? entry.trackID)
        case .appleMusic:
            AppleMusicHistoryScript.playDatabaseID(entry.trackID)
        case .qqMusic, .neteaseMusic:
            break
        }
    }

    func openLink(_ entry: PlaybackHistoryEntry) {
        guard let link = entry.trackLink, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    private func loadLocked() -> [PlaybackHistoryEntry] {
        if let cached { return cached }
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PlaybackHistoryEntry].self, from: data) else {
            cached = []
            return []
        }
        let valid = decoded.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if valid.count != decoded.count { saveLocked(valid) }
        cached = valid
        return valid
    }

    private func saveLocked(_ items: [PlaybackHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func merge(existing: PlaybackHistoryEntry, incoming: PlaybackHistoryEntry) -> PlaybackHistoryEntry {
        PlaybackHistoryEntry(
            id: existing.id,
            source: existing.source,
            trackID: existing.trackID,
            title: better(incoming.title, existing.title),
            artist: better(incoming.artist, existing.artist),
            album: better(incoming.album, existing.album),
            duration: incoming.duration > 0 ? incoming.duration : existing.duration,
            playedAt: incoming.playedAt,
            trackLink: incoming.trackLink ?? existing.trackLink,
            artworkPath: incoming.artworkPath ?? existing.artworkPath
        )
    }

    private func better(_ incoming: String, _ existing: String) -> String {
        incoming.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? existing : incoming
    }

    private func saveArtwork(_ image: NSImage?, id: String) -> String? {
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            return nil
        }
        let dir = artworkDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = id.replacingOccurrences(of: #"[^A-Za-z0-9_.-]+"#, with: "_", options: .regularExpression)
        let url = dir.appendingPathComponent("\(safeName).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    private func artworkDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MisLand/HistoryArtwork", isDirectory: true)
    }
}

private enum AppleMusicHistoryScript {
    static func playDatabaseID(_ id: String) {
        guard Int(id) != nil else { return }
        _ = run("""
        tell application "Music"
            try
                play (first track of library playlist 1 whose database ID is \(id))
            end try
        end tell
        """)
    }

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
        return String(data: data, encoding: .utf8)
    }
}
