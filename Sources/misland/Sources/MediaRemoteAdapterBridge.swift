import AppKit
import Foundation

/// Optional bridge for macOS versions that reject direct MediaRemote XPC calls
/// from normal apps. It uses the mediaremote-adapter Perl loader when available.
final class MediaRemoteAdapterBridge {
    static let shared = MediaRemoteAdapterBridge()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let lock = NSLock()
    private var cachedAt: Date?
    private var cachedItem: AdapterItem?

    private init() {}

    func snapshot(bundleID: String, timeout: TimeInterval = 0.7) -> MediaRemoteClientNowPlaying.Snapshot? {
        guard let item = currentItem(timeout: timeout),
              item.bundleIdentifier == bundleID,
              !item.title.isEmpty else {
            return nil
        }
        return MediaRemoteClientNowPlaying.Snapshot(
            bundleID: item.bundleIdentifier,
            title: item.title,
            artist: item.artist ?? "",
            album: item.album ?? "",
            duration: item.duration ?? 0,
            elapsed: item.elapsedTime ?? 0,
            playbackRate: item.playbackRate ?? (item.playing == true ? 1 : 0),
            timestamp: item.timestamp,
            artworkData: item.artworkData.flatMap { Data(base64Encoded: $0) }
        )
    }

    @discardableResult
    func send(command: Int, expectedBundleID: String) -> Bool {
        guard currentItem(timeout: 0.7)?.bundleIdentifier == expectedBundleID else { return false }
        return run(arguments: ["send", String(command)], timeout: 0.7)
    }

    @discardableResult
    func seek(to position: TimeInterval, expectedBundleID: String) -> Bool {
        guard currentItem(timeout: 0.7)?.bundleIdentifier == expectedBundleID else { return false }
        let micros = Int64((max(position, 0) * 1_000_000).rounded())
        return run(arguments: ["seek", String(micros)], timeout: 0.7)
    }

    private func currentItem(timeout: TimeInterval) -> AdapterItem? {
        let now = Date()
        lock.lock()
        if let cachedAt, now.timeIntervalSince(cachedAt) <= 0.35 {
            let item = cachedItem
            lock.unlock()
            return item
        }
        lock.unlock()

        guard let paths = locate() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script.path, paths.framework.path, "get"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        var data = Data()
        out.fileHandleForReading.readabilityHandler = { handle in
            data.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            process.terminate()
            out.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        out.fileHandleForReading.readabilityHandler = nil
        data.append(out.fileHandleForReading.readDataToEndOfFile())
        guard process.terminationStatus == 0 else { return nil }

        let item = try? decoder.decode(AdapterItem.self, from: data)
        lock.lock()
        cachedAt = now
        cachedItem = item
        lock.unlock()
        return item
    }

    private struct AdapterItem: Decodable {
        let bundleIdentifier: String
        let title: String
        let artist: String?
        let album: String?
        let duration: Double?
        let elapsedTime: Double?
        let playbackRate: Double?
        let timestamp: Date?
        let artworkData: String?
        let playing: Bool?
    }

    private struct BridgePaths {
        let script: URL
        let framework: URL
    }

    private func run(arguments: [String], timeout: TimeInterval) -> Bool {
        guard let paths = locate() else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script.path, paths.framework.path] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            process.terminate()
            return false
        }
        let ok = process.terminationStatus == 0
        if ok {
            lock.lock()
            cachedAt = nil
            cachedItem = nil
            lock.unlock()
        }
        return ok
    }

    private func locate() -> BridgePaths? {
        let bundle = Bundle.main
        let candidates: [BridgePaths] = [
            BridgePaths(
                script: bundle.resourceURL?.appendingPathComponent("mediaremote-adapter.pl")
                    ?? URL(fileURLWithPath: ""),
                framework: bundle.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework")
                    ?? URL(fileURLWithPath: "")
            ),
            BridgePaths(
                script: URL(fileURLWithPath: "/Users/shadycheer/Desktop/misland/tools/mediaremote-adapter/bin/mediaremote-adapter.pl"),
                framework: URL(fileURLWithPath: "/Users/shadycheer/Desktop/misland/tools/mediaremote-adapter/build/MediaRemoteAdapter.framework")
            ),
            BridgePaths(
                script: URL(fileURLWithPath: "/tmp/mediaremote-adapter/bin/mediaremote-adapter.pl"),
                framework: URL(fileURLWithPath: "/tmp/mediaremote-adapter/build/MediaRemoteAdapter.framework")
            ),
        ]
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.script.path)
                && FileManager.default.fileExists(atPath: $0.framework.path)
        }
    }
}
