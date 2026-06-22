// Accessibility probe for NetEase Cloud Music.
// Grants/uses AX permission, then dumps every text-bearing element in the app's
// UI tree so we can see whether the current song/artist is readable via AX.
//
// Build & run:  make axdump
import ApplicationServices
import AppKit

let bundleID = "com.netease.163music"

// Prompt to add this binary to System Settings ▸ Privacy ▸ Accessibility.
let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(opts)
print("AXIsProcessTrusted =", trusted)
if !trusted {
    print("""
    → Not trusted yet. A system prompt should appear (or open:
      System Settings ▸ Privacy & Security ▸ Accessibility),
      enable this binary (.build/axdump), then run `make axdump` again.
    """)
    exit(0)
}

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    print("NetEase (\(bundleID)) is not running."); exit(0)
}
let axApp = AXUIElementCreateApplication(app.processIdentifier)

func str(_ el: AXUIElement, _ attr: String) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
    if let s = v as? String, !s.isEmpty { return s }
    return nil
}

var count = 0
func walk(_ el: AXUIElement, _ depth: Int) {
    if depth > 25 || count > 4000 { return }
    count += 1
    let role = str(el, kAXRoleAttribute as String) ?? "?"
    let parts = [
        str(el, kAXValueAttribute as String).map { "value=\($0)" },
        str(el, kAXTitleAttribute as String).map { "title=\($0)" },
        str(el, kAXDescriptionAttribute as String).map { "desc=\($0)" },
        str(el, "AXHelp").map { "help=\($0)" }
    ].compactMap { $0 }
    if !parts.isEmpty {
        print(String(repeating: "  ", count: min(depth, 12)) + "[\(role)] " + parts.joined(separator: "  "))
    }
    var kids: CFTypeRef?
    if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids) == .success,
       let arr = kids as? [AXUIElement] {
        for k in arr { walk(k, depth + 1) }
    }
}

print("=== NetEase AX text dump (looking for song / artist) ===")
walk(axApp, 0)
print("=== done — scanned \(count) elements ===")
