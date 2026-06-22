import AppKit

/// Wrapper around Spotify desktop's bundled `spotify_cli` (Contents/MacOS/spotify_cli),
/// which talks to the running, logged-in desktop app's local desktop_api. Lets us
/// read/toggle "Liked Songs" locally — no OAuth, no Web API quota.
enum SpotifyCLI {
    /// Resolve the CLI inside whatever Spotify.app is installed; nil if absent.
    static var path: String? {
        guard let appURL = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.spotify.client") else { return nil }
        let cli = appURL.appendingPathComponent("Contents/MacOS/spotify_cli").path
        return FileManager.default.isExecutableFile(atPath: cli) ? cli : nil
    }

    static var isAvailable: Bool { path != nil }

    /// Run a command and return stdout. Synchronous — call off the main thread.
    @discardableResult
    private static func run(_ args: [String]) -> Data? {
        guard let path else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return data
    }

    /// Whether a track URI is in the user's Liked Songs. nil if unknown.
    static func isLiked(_ uri: String) -> Bool? {
        guard let data = run(["library", "contains", uri, "--format", "json"]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contains = obj["contains"] as? [String: Any],
              let liked = contains[uri] as? Bool else { return nil }
        return liked
    }

    /// Add/remove a track URI to/from Liked Songs.
    static func setLiked(_ uri: String, _ liked: Bool) {
        run(["library", liked ? "add" : "remove", uri])
    }
}
