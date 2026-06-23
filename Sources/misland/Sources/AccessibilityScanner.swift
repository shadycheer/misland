import AppKit
import ApplicationServices

/// Reads other apps' UI through the Accessibility API (AXUIElement). This is the
/// only viable local path for players that expose no scripting/CLI/now-playing
/// API (QQ音乐, 网易云音乐): scrape the window's static text for title/artist and
/// press the transport buttons. Requires the user to grant MisLand Accessibility
/// permission (System Settings → Privacy & Security → Accessibility).
///
/// First milestone: a tree DUMP so we can see the real element roles/labels and
/// build a reliable parser from them.
enum AccessibilityScanner {
    /// Bundle ids we target.
    static let qqMusic = "com.tencent.QQMusicMac"
    static let neteaseMusic = "com.netease.163music"

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompt for Accessibility permission (shows the system dialog once).
    static func requestPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Single-attribute helpers

    private static func attr(_ el: AXUIElement, _ key: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(el, key as CFString, &value) == .success ? value : nil
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    private static func actionNames(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        return AXUIElementCopyActionNames(el, &names) == .success ? (names as? [String]) ?? [] : []
    }

    private static func string(_ v: AnyObject?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    // MARK: - Tree dump (debugging step)

    /// Walk the app's AX tree and return an indented dump of every element's
    /// role / title / value / description / actions. Capped to stay readable.
    static func dumpTree(bundleID: String, maxDepth: Int = 14, maxNodes: Int = 4000) -> String {
        guard isTrusted else { return "NOT_TRUSTED — grant MisLand Accessibility permission first." }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return "\(bundleID): not running"
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var out = "AX dump for \(bundleID) (pid \(app.processIdentifier))\n"
        var count = 0
        func walk(_ el: AXUIElement, depth: Int) {
            if depth > maxDepth || count > maxNodes { return }
            count += 1
            let role = string(attr(el, kAXRoleAttribute as String)) ?? "?"
            let title = string(attr(el, kAXTitleAttribute as String))
            let value = string(attr(el, kAXValueAttribute as String))
            let desc = string(attr(el, kAXDescriptionAttribute as String))
            let help = string(attr(el, kAXHelpAttribute as String))
            let acts = actionNames(el).filter { $0 != "AXShowMenu" }
            var line = String(repeating: "  ", count: depth) + role
            if let title, !title.isEmpty { line += " | title=\"\(title)\"" }
            if let value, !value.isEmpty { line += " | value=\"\(value)\"" }
            if let desc, !desc.isEmpty { line += " | desc=\"\(desc)\"" }
            if let help, !help.isEmpty { line += " | help=\"\(help)\"" }
            if !acts.isEmpty { line += " | actions=\(acts)" }
            out += line + "\n"
            for child in children(el) { walk(child, depth: depth + 1) }
        }
        walk(axApp, depth: 0)
        out += "\n(\(count) nodes)\n"
        return out
    }

    /// Dump QQ + NetEase trees to ~/Desktop so we can design the parser.
    @discardableResult
    static func dumpTargetsToDesktop() -> String {
        if !isTrusted { requestPermission(); return "Requested Accessibility permission — grant it, then dump again." }
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        var report = ""
        for (name, bid) in [("qqmusic", qqMusic), ("netease", neteaseMusic)] {
            let dump = dumpTree(bundleID: bid)
            let url = desktop.appendingPathComponent("misland-ax-\(name).txt")
            try? dump.write(to: url, atomically: true, encoding: .utf8)
            report += "\(name): \(url.path)\n"
        }
        return report
    }
}
