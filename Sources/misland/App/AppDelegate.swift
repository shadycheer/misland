import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
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
    private var currentScreenFrame: CGRect = .null
    private var currentScreen: NSScreen?
    private var browserOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
        UserDefaults.standard.register(defaults: [
            "showExportButton": true, "autoPeek": true, "exclusivePlayback": true,
        ])
        coordinator = PlaybackCoordinator(sources: sources)

        let initial = NSScreen.main ?? screenUnderCursor() ?? NSScreen.screens.first
        geo = initial.map(geometry(for:)) ?? geo
        islandState.geo = geo

        let host = NSHostingView(rootView:
            IslandRootView(coordinator: coordinator, islandState: islandState,
                           onBrowserResize: { [weak self] open in self?.setBrowser(open: open) },
                           onSettingsMenu: { [weak self] in self?.popUpAppMenu() })
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
        if let initial { place(on: initial) }
        window.orderFrontRegardless()

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

    private func screenUnderCursor() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
    }

    /// Follow the *active* display — the screen whose window has keyboard focus
    /// (i.e. where you clicked/are working), not the mouse. Cheap; called on app
    /// switches and each poll. Won't yank the island mid-hover.
    private func updateActiveScreen() {
        guard !islandState.expanded, let target = NSScreen.main,
              target.frame != currentScreenFrame else { return }
        place(on: target)
    }

    private func geometry(for screen: NSScreen) -> IslandGeometry {
        let notch = NotchGeometry.notchSize(
            forScreenWidth: screen.frame.width,
            safeAreaTop: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )
        let bar = max(screen.frame.maxY - screen.visibleFrame.maxY, 22) // menu bar height
        return IslandGeometry(hasNotch: notch.height > 0,
                              notchWidth: notch.width, notchHeight: notch.height,
                              barHeight: bar)
    }

    /// Move the island to `screen`: recompute geometry (notch vs floating),
    /// reposition the window top-center, and refresh hit rects.
    private func place(on screen: NSScreen) {
        currentScreen = screen
        currentScreenFrame = screen.frame
        geo = geometry(for: screen)
        islandState.geo = geo
        window.place(on: screen, size: expandedSize)
        computeRects()
    }

    /// The browser makes the panel taller; resize the fixed window (and refresh
    /// hit rects) so the expanded screen rect matches what's drawn.
    private func setBrowser(open: Bool) {
        guard browserOpen != open else { return }
        browserOpen = open
        guard let screen = currentScreen else { return }
        window.place(on: screen, size: expandedSize)
        computeRects()
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
        let content = browserOpen ? IslandLayout.browserHeight : IslandLayout.expandedHeight
        let strip = geo.hasNotch ? geo.notchHeight : IslandLayout.noNotchStripHeight
        return CGSize(width: IslandLayout.expandedWidth, height: strip + content)
    }

    private var collapsedSize: CGSize {
        geo.hasNotch
            ? CGSize(width: geo.notchWidth + 2 * IslandLayout.sideWidth, height: geo.notchHeight)
            : CGSize(width: IslandLayout.collapsedWidth, height: geo.barHeight)
    }

    /// Build a fresh menu (更多设置 / 退出) bound to this app delegate — used by
    /// the gear button and the island's right-click menu (no menu-bar icon).
    private func makeAppMenu() -> NSMenu {
        let menu = NSMenu()
        let prefs = NSMenuItem(title: "更多设置…", action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        return menu
    }

    /// Pop the settings menu at the cursor. NSMenu runs its own tracking loop, so
    /// it works even though the panel never becomes key.
    private func popUpAppMenu() {
        makeAppMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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
            self?.updateActiveScreen()
        }
        // React promptly when you switch to an app on another display.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateActiveScreen() }
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
