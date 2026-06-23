import SwiftUI
import AppKit
import ServiceManagement

/// Register/unregister MisLand as a login item (macOS 13+ SMAppService).
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("MisLand launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}

struct PreferencesView: View {
    @AppStorage("showExportButton") private var showExportButton = true
    @AppStorage("autoPeek") private var autoPeek = true
    @AppStorage("exclusivePlayback") private var exclusivePlayback = true
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Section("通用") {
                        ToggleRow("开机时自动启动", "登录 Mac 时自动运行 MisLand",
                                  isOn: $launchAtLogin) { LaunchAtLogin.set($0) }
                    }
                    Section("播放") {
                        ToggleRow("独占播放", "同一时间只放一个播放器，切换时自动暂停另一个",
                                  isOn: $exclusivePlayback)
                    }
                    Section("外观与行为") {
                        ToggleRow("显示导出卡片按钮", "展开播放器时显示「分享卡片」按钮",
                                  isOn: $showExportButton)
                        RowDivider()
                        ToggleRow("切歌自动探头", "换歌时自动弹出约 2 秒再收回",
                                  isOn: $autoPeek)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            footer
        }
        .frame(width: 460, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text("MisLand").font(.system(size: 19, weight: .bold))
                Text("把正在播放的单曲，放进 Mac 刘海里")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("v\(version)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var footer: some View {
        HStack {
            Link(destination: URL(string: "https://github.com/shadycheer/misland")!) {
                HStack(spacing: 5) {
                    Image(systemName: "link").font(.system(size: 10))
                    Text("GitHub").font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            Text("纯本地 · 无遥测").font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(Color.primary.opacity(0.02))
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Color.primary.opacity(0.08)), alignment: .top)
    }
}

// MARK: - Building blocks

/// A titled, full-width settings group (uppercase caption + rounded card).
private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Inset hairline between rows inside a card.
private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var onChange: ((Bool) -> Void)? = nil

    init(_ title: String, _ subtitle: String, isOn: Binding<Bool>, onChange: ((Bool) -> Void)? = nil) {
        self.title = title; self.subtitle = subtitle; self._isOn = isOn; self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onChange(of: isOn) { _, v in onChange?(v) }
    }
}

/// Single, reusable preferences window for the menu-bar agent.
final class PreferencesWindowController {
    static let shared = PreferencesWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            w.title = "MisLand 设置"
            w.contentView = NSHostingView(rootView: PreferencesView())
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
