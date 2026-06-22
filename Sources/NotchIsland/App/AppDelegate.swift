import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NotchWindow!
    private var container: PassthroughContainer!
    private var coordinator: PlaybackCoordinator!
    private var timer: Timer?
    private var geo = IslandGeometry(hasNotch: false, notchWidth: 0, notchHeight: 0)
    private let sources: [NowPlayingSource] = [SpotifySource(), AppleMusicSource()]
    private let pollQueue = DispatchQueue(label: "com.shadycheer.notchisland.poll")
    private var islandScreenRect: CGRect = .zero   // current interactive area, screen coords
    private var mouseMonitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
        coordinator = PlaybackCoordinator(sources: sources)

        // Prefer the built-in notched screen (NSScreen.main follows keyboard
        // focus, which may be an external display).
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
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

        // Fixed full-size window; only the island animates inside it. The
        // container passes mouse events through everywhere except the island.
        container = PassthroughContainer(frame: CGRect(origin: .zero, size: expandedSize))
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])

        window = NotchWindow(rootView: container)
        if let screen { window.place(on: screen, size: expandedSize) }
        setExpanded(false)
        window.orderFrontRegardless()

        setupStatusItem()
        setupMouseMonitors()
        observeDistributedNotifications()
        startPolling()
        pollOnce()
    }

    /// The window is a fixed full-size overlay; to let clicks reach apps below
    /// everywhere except the island, watch the global cursor and toggle
    /// ignoresMouseEvents — the only reliable cross-app / fullscreen passthrough.
    /// (mouseMoved monitors need no special permission.)
    private func setupMouseMonitors() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.updateClickThrough()
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updateClickThrough()
            return event
        }
        mouseMonitors = [global, local].compactMap { $0 }
        updateClickThrough()
    }

    private func updateClickThrough() {
        let shouldIgnore = !islandScreenRect.contains(NSEvent.mouseLocation)
        if window.ignoresMouseEvents != shouldIgnore {
            window.ignoresMouseEvents = shouldIgnore
        }
    }

    /// Read the players off the main thread (ScriptingBridge is synchronous IPC),
    /// then publish to the observable coordinator on the main thread.
    private func pollOnce(signal: SourceKind? = nil) {
        pollQueue.async { [weak self] in
            guard let self else { return }
            if let signal { self.coordinator.sourceDidSignal(signal) }
            let snapshot = self.coordinator.readSnapshot()
            DispatchQueue.main.async { self.coordinator.publish(snapshot) }
        }
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

    /// Update which region of the fixed window is mouse-interactive (top-center,
    /// sized to the current island). No window resize → animation stays smooth.
    private func setExpanded(_ expanded: Bool) {
        let full = expandedSize
        let s = expanded ? full : collapsedSize
        let rect = CGRect(
            x: (full.width - s.width) / 2,
            y: full.height - s.height,
            width: s.width,
            height: s.height
        )
        container.activeRect = rect
        // Same rect in screen coordinates, for the click-through monitor.
        islandScreenRect = CGRect(
            x: window.frame.minX + rect.minX,
            y: window.frame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
        updateClickThrough()
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
            self?.pollOnce(signal: .spotify)
        }
        dnc.addObserver(forName: .init("com.apple.Music.playerInfo"),
                        object: nil, queue: .main) { [weak self] _ in
            self?.pollOnce(signal: .appleMusic)
        }
    }

    private func startPolling() {
        // Poll twice a second so the progress bar advances smoothly. Work runs
        // off-main via pollOnce, so it never stutters the UI/animation.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollOnce()
        }
    }

    /// `open -n` can spawn multiple copies; extra instances each poll and draw
    /// their own island, which looks like jank. Keep only this one.
    private func terminateOtherInstances() {
        let current = NSRunningApplication.current
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier == current.bundleIdentifier
            && app.processIdentifier != current.processIdentifier {
            app.forceTerminate()
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
