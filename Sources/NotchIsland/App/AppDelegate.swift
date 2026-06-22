import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NotchWindow!
    private var coordinator: PlaybackCoordinator!
    private var timer: Timer?
    private var screenRef: NSScreen?
    private var geo = IslandGeometry(hasNotch: false, notchWidth: 0, notchHeight: 0)
    private let sources: [NowPlayingSource] = [SpotifySource(), AppleMusicSource()]

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = PlaybackCoordinator(sources: sources)

        let screen = NSScreen.main
        screenRef = screen
        let notch = screen.map {
            NotchGeometry.notchSize(
                forScreenWidth: $0.frame.width,
                safeAreaTop: $0.safeAreaInsets.top,
                leftArea: $0.auxiliaryTopLeftArea,
                rightArea: $0.auxiliaryTopRightArea
            )
        } ?? .zero
        geo = IslandGeometry(hasNotch: notch.height > 0,
                             notchWidth: notch.width, notchHeight: notch.height)

        let host = NSHostingView(rootView:
            IslandRootView(coordinator: coordinator, geo: geo,
                           onExpandChange: { [weak self] in self?.setExpanded($0) })
        )
        host.translatesAutoresizingMaskIntoConstraints = false

        // Container is sized to the largest (expanded) footprint; the window
        // resizes its content view, so the host (pinned top-center) tracks it.
        window = NotchWindow(rootView: hostContainer(host, size: expandedSize))
        setExpanded(false, animated: false)
        window.orderFrontRegardless()

        setupStatusItem()
        observeDistributedNotifications()
        startPolling()
        coordinator.refresh()
    }

    private var expandedSize: CGSize {
        geo.hasNotch
            ? CGSize(width: IslandLayout.expandedWidth, height: geo.notchHeight + IslandLayout.expandedHeight)
            : CGSize(width: IslandLayout.expandedWidth, height: IslandLayout.expandedHeight)
    }

    private var collapsedSize: CGSize {
        geo.hasNotch
            ? CGSize(width: geo.notchWidth + 2 * IslandLayout.sideWidth, height: geo.notchHeight)
            : CGSize(width: IslandLayout.collapsedWidth, height: IslandLayout.collapsedHeight)
    }

    private func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard let screen = screenRef else { return }
        let s = expanded ? expandedSize : collapsedSize
        window.setFrameCentered(on: screen, width: s.width, height: s.height, animated: animated)
    }

    /// Pin the host to the top-center of the panel; it grows downward as the
    /// SwiftUI content (and window) expand.
    private func hostContainer(_ host: NSView, size: CGSize) -> NSView {
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
        return container
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "NotchIsland")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit NotchIsland", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func observeDistributedNotifications() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"),
                        object: nil, queue: .main) { [weak self] _ in
            self?.coordinator.sourceDidSignal(.spotify)
            self?.coordinator.refresh()
        }
        dnc.addObserver(forName: .init("com.apple.Music.playerInfo"),
                        object: nil, queue: .main) { [weak self] _ in
            self?.coordinator.sourceDidSignal(.appleMusic)
            self?.coordinator.refresh()
        }
    }

    private func startPolling() {
        // Cheap now that artwork is cached — poll twice a second so the
        // progress bar advances smoothly.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.coordinator.refresh()
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
