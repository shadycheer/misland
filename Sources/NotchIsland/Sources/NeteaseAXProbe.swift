import ApplicationServices
import AppKit

/// Debug helper: dump NetEase Cloud Music's Accessibility tree so we can see
/// whether the current song/artist is readable via AX (it's a CEF app, so the
/// Chromium accessibility tree is likely populated once AX is trusted).
enum NeteaseAXProbe {
    static let bundleID = "com.netease.163music"
    static let outputPath = "/tmp/netease-ax.txt"

    /// Returns a short status line; writes the full dump to `outputPath`.
    @discardableResult
    static func dump() -> String {
        guard AXIsProcessTrusted() else {
            return "未授权辅助功能 — 去 系统设置▸隐私与安全性▸辅助功能 打开 NotchIsland 后重试"
        }
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first else {
            return "网易云未运行"
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var out = "=== NetEase AX dump ===\n"
        var count = 0
        walk(axApp, 0, &out, &count)
        out += "=== scanned \(count) elements ===\n"
        try? out.write(toFile: outputPath, atomically: true, encoding: .utf8)
        return "已导出 \(count) 个元素 → \(outputPath)"
    }

    private static func str(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        if let s = v as? String, !s.isEmpty { return s }
        return nil
    }

    private static func walk(_ el: AXUIElement, _ depth: Int, _ out: inout String, _ count: inout Int) {
        if depth > 25 || count > 5000 { return }
        count += 1
        let role = str(el, kAXRoleAttribute as String) ?? "?"
        let parts = [
            str(el, kAXValueAttribute as String).map { "value=\($0)" },
            str(el, kAXTitleAttribute as String).map { "title=\($0)" },
            str(el, kAXDescriptionAttribute as String).map { "desc=\($0)" }
        ].compactMap { $0 }
        if !parts.isEmpty {
            out += String(repeating: "  ", count: min(depth, 12)) + "[\(role)] " + parts.joined(separator: "  ") + "\n"
        }
        var kids: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids) == .success,
           let arr = kids as? [AXUIElement] {
            for k in arr { walk(k, depth + 1, &out, &count) }
        }
    }
}
