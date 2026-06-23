import AppKit
import ApplicationServices

/// Low-level Accessibility (AXUIElement) helpers shared by AX-based sources.
/// All reads are synchronous IPC — call off the main thread for polling; UI
/// actions (button presses) are fine on main. Requires Accessibility permission.
enum AXUI {
    static func runningApp(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    static func appElement(_ bundleID: String) -> AXUIElement? {
        guard let app = runningApp(bundleID) else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    static func attr(_ el: AXUIElement, _ key: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, key as CFString, &v) == .success ? v : nil
    }

    static func str(_ el: AXUIElement, _ key: String) -> String? {
        let v = attr(el, key)
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func element(_ el: AXUIElement, _ key: String) -> AXUIElement? {
        guard let v = attr(el, key), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func children(_ el: AXUIElement) -> [AXUIElement] {
        (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    static func windows(_ app: AXUIElement) -> [AXUIElement] {
        (attr(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    }

    static func desc(_ el: AXUIElement) -> String? { str(el, kAXDescriptionAttribute as String) }
    static func title(_ el: AXUIElement) -> String? { str(el, kAXTitleAttribute as String) }

    @discardableResult
    static func press(_ el: AXUIElement) -> Bool {
        AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }

    /// Press a menu item (by exact title) inside a top menu-bar item. The menu's
    /// items are present in the AX tree even while the menu is closed.
    @discardableResult
    static func pressMenuItem(_ app: AXUIElement, menu menuTitle: String, titleIn options: [String]) -> Bool {
        guard let bar = element(app, kAXMenuBarAttribute as String) else { return false }
        guard let barItem = children(bar).first(where: { title($0) == menuTitle }),
              let menu = children(barItem).first else { return false }
        for item in children(menu) where options.contains(title(item) ?? "") {
            return press(item)
        }
        return false
    }
}
