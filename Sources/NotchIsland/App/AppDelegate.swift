import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NotchWindow!
    private var coordinator: PlaybackCoordinator!
    private var timer: Timer?
    private let sources: [NowPlayingSource] = [SpotifySource(), AppleMusicSource()]

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = PlaybackCoordinator(sources: sources)

        let canLike = sources.contains { $0.canSetLiked }
        let host = NSHostingView(rootView:
            IslandRootView(coordinator: coordinator, canLike: canLike)
        )
        host.translatesAutoresizingMaskIntoConstraints = false

        window = NotchWindow(rootView: hostContainer(host))
        if let screen = NSScreen.main {
            window.reposition(on: screen, size: CGSize(width: 220, height: 32))
        }
        window.orderFrontRegardless()

        setupStatusItem()
        observeDistributedNotifications()
        startPolling()
        coordinator.refresh()
    }

    /// Wraps the hosting view pinned to the top-center of the panel so the
    /// island grows downward from the notch.
    private func hostContainer(_ host: NSView) -> NSView {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 430, height: 240))
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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.coordinator.refresh()
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
