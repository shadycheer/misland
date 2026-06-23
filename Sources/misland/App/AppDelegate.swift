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
    private let pollQueue = DispatchQueue(label: "com.shadycheer.misland.poll")
    private let islandState = IslandState()
    private var collapsedScreenRect: CGRect = .zero  // exact screen rect of the pill
    private var expandedScreenRect: CGRect = .zero   // exact screen rect when expanded
    private var mouseMonitors: [Any] = []
    private var dwellWork: DispatchWorkItem?

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
            IslandRootView(coordinator: coordinator, geo: geo, islandState: islandState)
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

        // Right-clicking the island shows the same menu — works even when the
        // menu-bar icon is hidden behind a full notch (NSView.menu pops up
        // without the panel needing to become key, unlike SwiftUI .contextMenu).
        container.menu = makeAppMenu()

        window = NotchWindow(rootView: container)
        if let screen { window.place(on: screen, size: expandedSize) }
        computeRects()
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
            self?.onMouseMoved()
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.onMouseMoved()
            return event
        }
        mouseMonitors = [global, local].compactMap { $0 }
        onMouseMoved()
    }

    /// Single source of truth for hover: is the cursor inside the island's exact
    /// screen rect? Drives both click-through and (with a dwell) the expand state.
    private func onMouseMoved() {
        let loc = NSEvent.mouseLocation
        // The collapsed pill exists whenever there's a track (playing or paused);
        // the expanded panel only while already hovering. Idle = nothing to hit.
        let hasTrack = coordinator.track != nil
        let activeRect = islandState.expanded ? expandedScreenRect
            : (hasTrack ? collapsedScreenRect : .null)
        let inside = activeRect.contains(loc)

        if window.ignoresMouseEvents != !inside { window.ignoresMouseEvents = !inside }

        if inside {
            if !islandState.hovering, dwellWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    self?.islandState.hovering = true
                    self?.dwellWork = nil
                }
                dwellWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            }
        } else {
            dwellWork?.cancel(); dwellWork = nil
            if islandState.hovering { islandState.hovering = false }
        }
    }

    /// Exact screen rects of the collapsed pill and the expanded panel, both
    /// top-centered within the fixed window.
    private func computeRects() {
        let f = window.frame
        let c = collapsedSize
        collapsedScreenRect = CGRect(
            x: f.minX + (f.width - c.width) / 2,
            y: f.maxY - c.height,
            width: c.width, height: c.height
        )
        expandedScreenRect = f
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

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "MisLand")
        statusItem.menu = makeAppMenu()
    }

    /// Build a fresh menu (Preferences / Quit) with targets bound to this app
    /// delegate. Used by both the status item and the island's right-click menu.
    private func makeAppMenu() -> NSMenu {
        let menu = NSMenu()
        let prefs = NSMenuItem(title: "偏好设置…", action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        let quitItem = NSMenuItem(title: "退出 MisLand", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        return menu
    }

    @objc private func showPreferences() {
        PreferencesWindowController.shared.show()
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
