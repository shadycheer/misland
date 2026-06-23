import ApplicationServices
import AppKit
import Foundation
import Darwin.Mach

let bundleID = "com.tencent.QQMusicMac"

func run(_ path: String, _ args: [String]) -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = args
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = Pipe()
    do { try proc.run() } catch { return "" }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

func attr<T>(_ el: AXUIElement, _ name: String, as: T.Type = T.self) -> T? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
    return value as? T
}

func stringAttr(_ el: AXUIElement, _ name: String) -> String? {
    attr(el, name, as: NSString.self) as String?
}

func numberAttr(_ el: AXUIElement, _ name: String) -> Double? {
    if let n = attr(el, name, as: NSNumber.self) { return n.doubleValue }
    return nil
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    attr(el, kAXChildrenAttribute, as: NSArray.self) as? [AXUIElement] ?? []
}

func interesting(_ el: AXUIElement) -> Bool {
    let fields = [
        stringAttr(el, kAXRoleAttribute),
        stringAttr(el, kAXSubroleAttribute),
        stringAttr(el, kAXTitleAttribute),
        stringAttr(el, kAXDescriptionAttribute),
        stringAttr(el, kAXHelpAttribute),
        stringAttr(el, kAXValueAttribute),
    ].compactMap { $0 }.joined(separator: " ").lowercased()
    let needles = [
        "progress", "slider", "valueindicator", "time", "duration",
        "position", "seek", "播放进度", "进度", "时长", "时间", "已播放",
        "0:", "1:", "2:", "3:", "4:", "5:", "6:", "7:", "8:", "9:"
    ]
    return needles.contains { fields.contains($0.lowercased()) }
        || numberAttr(el, kAXValueAttribute) != nil
        || numberAttr(el, kAXMinValueAttribute) != nil
        || numberAttr(el, kAXMaxValueAttribute) != nil
}

func describe(_ el: AXUIElement) -> String {
    var parts: [String] = []
    for name in [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXTitleAttribute,
        kAXDescriptionAttribute,
        kAXHelpAttribute,
        kAXValueAttribute,
        kAXMinValueAttribute,
        kAXMaxValueAttribute,
        "AXShownMenu",
    ] {
        if let s = stringAttr(el, name) {
            parts.append("\(name)=\(s)")
        } else if let n = numberAttr(el, name) {
            parts.append("\(name)=\(n)")
        }
    }
    return parts.joined(separator: " | ")
}

func walk(_ el: AXUIElement, depth: Int = 0, maxDepth: Int = 12, seen: inout Int) {
    guard depth <= maxDepth, seen < 3000 else { return }
    seen += 1
    if interesting(el) {
        print(String(repeating: "  ", count: depth) + describe(el))
    }
    for child in children(el) {
        walk(child, depth: depth + 1, maxDepth: maxDepth, seen: &seen)
    }
}

print("== QQ progress probe ==")
let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
guard let app = apps.first else {
    print("QQMusic not running")
    exit(1)
}
print("pid=\(app.processIdentifier)")
print("AXTrusted=\(AXIsProcessTrusted())")

var task: mach_port_name_t = 0
let kr = task_for_pid(mach_task_self_, app.processIdentifier, &task)
print("task_for_pid=\(kr) task=\(task)")

print("\n== AX interesting elements ==")
let ax = AXUIElementCreateApplication(app.processIdentifier)
var seen = 0
walk(ax, seen: &seen)
print("AXVisited=\(seen)")

print("\n== Open mapped state files ==")
let lsof = run("/usr/sbin/lsof", ["-Pan", "-p", String(app.processIdentifier)])
for line in lsof.split(separator: "\n") {
    let s = String(line)
    if s.contains("QQMusicMac") &&
        (s.contains("iData") || s.contains("mmkv") || s.contains("mmap") || s.contains("sqlite") || s.contains("shm") || s.contains("wal")) {
        print(s)
    }
}
