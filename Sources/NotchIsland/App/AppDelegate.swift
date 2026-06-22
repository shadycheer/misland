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

        let screen = NSScreen.main
        let notch = screen.map {
            NotchGeometry.notchSize(
                forScreenWidth: $0.frame.width,
                safeAreaTop: $0.safeAreaInsets.top,
                leftArea: $0.auxiliaryTopLeftArea,
                rightArea: $0.auxiliaryTopRightArea
            )
        } ?? .zero
        // Black strip behind the notch so the panel fuses with it (0 = no notch).
        let topInset = notch.height
        let collapsedWidth = notch.width > 0 ? notch.width : IslandLayout.collapsedWidth
        let contentHeight = topInset + IslandLayout.expandedHeight

        let host = NSHostingView(rootView:
            IslandRootView(coordinator: coordinator, topInset: topInset, collapsedWidth: collapsedWidth)
        )
        host.translatesAutoresizingMaskIntoConstraints = false

        // Pin the host to the very top so its black top edge fuses with the notch.
        window = NotchWindow(rootView: hostContainer(host, height: contentHeight))
        if let screen { window.place(on: screen, contentHeight: contentHeight) }
        window.orderFrontRegardless()

        setupStatusItem()
        observeDistributedNotifications()
        startPolling()
        coordinator.refresh()
    }

    /// Wraps the hosting view pinned to the very top-center of the panel; the
    /// view itself reserves the notch height internally so the panel's black top
    /// edge fuses with the notch.
    private func hostContainer(_ host: NSView, height: CGFloat) -> NSView {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: IslandLayout.expandedWidth, height: height))
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
