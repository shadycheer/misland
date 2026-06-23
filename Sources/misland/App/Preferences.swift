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
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return v ?? "0.1"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Card(title: "通用") {
                        ToggleRow(title: "开机时自动启动",
                                  subtitle: "登录 Mac 时自动运行 MisLand",
                                  isOn: $launchAtLogin) { LaunchAtLogin.set($0) }
                    }
                    Card(title: "播放") {
                        ToggleRow(title: "独占播放",
                                  subtitle: "同一时间只放一个播放器，切换时自动暂停另一个",
                                  isOn: $exclusivePlayback)
                    }
                    Card(title: "外观与行为") {
                        ToggleRow(title: "显示导出卡片按钮",
                                  subtitle: "展开播放器时显示「分享卡片」按钮",
                                  isOn: $showExportButton)
                        Divider().padding(.leading, 12)
                        ToggleRow(title: "切歌自动探头",
                                  subtitle: "换歌时自动弹出约 2 秒再收回",
                                  isOn: $autoPeek)
                    }
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(width: 440, height: 420)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("MisLand").font(.system(size: 18, weight: .bold))
                Text("把正在播放的单曲，放进 Mac 刘海里")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("v\(version)")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack {
            Link(destination: URL(string: "https://github.com/shadycheer/misland")!) {
                HStack(spacing: 4) {
                    Image(systemName: "link").font(.system(size: 10))
                    Text("GitHub").font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            Text("纯本地 · 无遥测").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Building blocks

/// A titled, rounded settings group.
private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                )
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding private var isOnDirect: Bool
    private let usesDirect: Bool
    private let onChange: ((Bool) -> Void)?
    @Environment(\.isOnBinding) private var envBinding

    init(title: String, subtitle: String, isOn: Binding<Bool>, onChange: ((Bool) -> Void)? = nil) {
        self.title = title; self.subtitle = subtitle
        self._isOnDirect = isOn; self.usesDirect = true; self.onChange = onChange
    }

    /// Variant whose binding is injected via the environment (lets callers chain
    /// `.environment(\.isOnBinding, $x)` for readability).
    init(title: String, subtitle: String) {
        self.title = title; self.subtitle = subtitle
        self._isOnDirect = .constant(false); self.usesDirect = false; self.onChange = nil
    }

    private var binding: Binding<Bool> { usesDirect ? $isOnDirect : (envBinding ?? .constant(false)) }

    var body: some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .onChange(of: binding.wrappedValue) { _, v in onChange?(v) }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct IsOnBindingKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}
extension EnvironmentValues {
    var isOnBinding: Binding<Bool>? {
        get { self[IsOnBindingKey.self] }
        set { self[IsOnBindingKey.self] = newValue }
    }
}

/// Single, reusable preferences window for the menu-bar agent.
final class PreferencesWindowController {
    static let shared = PreferencesWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
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
