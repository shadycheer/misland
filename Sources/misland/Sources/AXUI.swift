import AppKit
import ApplicationServices

/// Low-level Accessibility (AXUIElement) helpers shared by AX-based sources.
/// All reads are synchronous IPC — call off the main thread for polling; UI
/// actions (button presses) are fine on main. Requires Accessibility permission.
enum AXUI {
    private static var didPromptForTrust = false

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Ask macOS to show the Accessibility permission prompt once. Polling code
    /// can call this safely; repeated calls only re-check the current state.
    @discardableResult
    static func requestTrustIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }
        guard !didPromptForTrust else { return false }
        didPromptForTrust = true
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

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

    static func firstDescendant(
        of root: AXUIElement,
        maxDepth: Int = 10,
        where matches: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        func walk(_ el: AXUIElement, depth: Int) -> AXUIElement? {
            if matches(el) { return el }
            guard depth < maxDepth else { return nil }
            for child in children(el) {
                if let found = walk(child, depth: depth + 1) { return found }
            }
            return nil
        }
        return walk(root, depth: 0)
    }

    static func desc(_ el: AXUIElement) -> String? { str(el, kAXDescriptionAttribute as String) }
    static func title(_ el: AXUIElement) -> String? { str(el, kAXTitleAttribute as String) }
    static func help(_ el: AXUIElement) -> String? { str(el, kAXHelpAttribute as String) }

    static func actionNames(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        return AXUIElementCopyActionNames(el, &names) == .success ? (names as? [String]) ?? [] : []
    }

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
        if children(menu).isEmpty {
            _ = AXUIElementPerformAction(barItem, kAXShowMenuAction as CFString)
        }
        for item in children(menu) where options.contains(title(item) ?? "") {
            return press(item)
        }
        return false
    }

    @discardableResult
    static func pressAnyMenuItem(_ app: AXUIElement, menus: [String], titleIn options: [String]) -> Bool {
        for menu in menus where pressMenuItem(app, menu: menu, titleIn: options) {
            return true
        }
        return false
    }

    @discardableResult
    static func pressFirstDescendant(in app: AXUIElement, labels: [String]) -> Bool {
        for window in windows(app) {
            if let target = firstDescendant(of: window, maxDepth: 14, where: { el in
                guard actionNames(el).contains(kAXPressAction as String) else { return false }
                let values = [title(el), desc(el), help(el)].compactMap { $0 }
                return values.contains { value in
                    labels.contains { label in value == label || value.contains(label) }
                }
            }) {
                return press(target)
            }
        }
        return false
    }
}
