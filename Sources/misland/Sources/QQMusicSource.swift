import AppKit
import ApplicationServices

/// QQ音乐 has no scripting/CLI/now-playing API, but its native playback bar IS
/// exposed via Accessibility: one element's description encodes the song
/// ("歌曲名：X - 歌手名：Y"), the play button's description gives the play state,
/// and the menu bar "播放控制" offers pressable transport. So we read from the AX
/// tree and control through menu-bar AXPress. Requires Accessibility permission.
///
/// Limitations (AX exposes nothing more): no album art, no position/duration.
final class QQMusicSource: NowPlayingSource {
    let kind: SourceKind = .qqMusic
    var canSetLiked: Bool { AXUI.isTrusted }

    private let bundleID = "com.tencent.QQMusicMac"

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

    func currentTrack() -> Track? {
        guard let bar = playbar() else { return nil }
        var title: String?
        var artist = ""
        var liked: Bool?
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
            } else if d.contains("喜欢歌曲") || d == "喜欢" {
                liked = false
            }
        }
        guard let title, !title.isEmpty else { return nil }
        return Track(id: "qq:\(title)|\(artist)", title: title, artist: artist,
                     album: "", duration: 0, artwork: nil, isLiked: liked)
    }

    func currentState() -> PlaybackState? {
        guard let bar = playbar() else { return nil }
        // The toggle button reads "暂停" while playing, "播放" while paused.
        var playing: Bool?
        for el in AXUI.children(bar) {
            switch AXUI.desc(el) {
            case "暂停": playing = true
            case "播放": playing = false
            default: continue
            }
        }
        guard let playing else { return nil }
        return PlaybackState(isPlaying: playing, position: 0, source: .qqMusic)
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

    func seek(to position: TimeInterval) { /* AX exposes no seekable position */ }

    func setLiked(_ liked: Bool) {
        guard AXUI.requestTrustIfNeeded(), let app = app() else { return }
        // One toggle item, titled for its action ("喜欢歌曲" to like / "取消喜欢" to unlike).
        AXUI.pressMenuItem(app, menu: "播放控制", titleIn: liked ? ["喜欢歌曲"] : ["取消喜欢"])
    }
}
