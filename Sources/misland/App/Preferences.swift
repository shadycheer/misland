import SwiftUI
import AppKit

struct PreferencesView: View {
    @AppStorage("showExportButton") private var showExportButton = true
    @AppStorage("autoPeek") private var autoPeek = true
    @AppStorage("exclusivePlayback") private var exclusivePlayback = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MisLand").font(.system(size: 15, weight: .semibold))
            Toggle("同一时间只放一个播放器（切换时自动暂停另一个）", isOn: $exclusivePlayback)
            Toggle("展开时显示「导出卡片」按钮", isOn: $showExportButton)
            Toggle("切歌时自动探头 2 秒", isOn: $autoPeek)
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 380, height: 200, alignment: .topLeading)
    }
}

/// Single, reusable preferences window for the menu-bar agent.
final class PreferencesWindowController {
    static let shared = PreferencesWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            w.title = "偏好设置"
            w.contentView = NSHostingView(rootView: PreferencesView())
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
