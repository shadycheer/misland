# Notch Music Island Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu-bar app that shows the current Spotify / Apple Music track as a notch-fused island (collapsed pill → hover-expanded player with art, progress, transport controls, and like).

**Architecture:** A Swift Package executable packaged into a `.app` bundle (LSUIElement agent). Player access is abstracted behind a `NowPlayingSource` protocol with two ScriptingBridge implementations; a `PlaybackCoordinator` selects the active source and publishes a unified observable state to SwiftUI views hosted in a borderless non-activating `NSPanel` aligned to the notch.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (`NSPanel`, `NSStatusItem`, `NSScreen`), ScriptingBridge (`SBApplication`), Swift Package Manager, XCTest.

---

## File Structure

```
Package.swift
Sources/NotchIsland/
  main.swift                  — entry: NSApplication + AppDelegate bootstrap
  App/AppDelegate.swift       — status item, NotchWindow lifecycle, coordinator wiring
  Model/Track.swift           — Track, PlaybackState, SourceKind
  Sources/NowPlayingSource.swift   — protocol + control capability
  Sources/SpotifySource.swift      — ScriptingBridge to Spotify.app
  Sources/AppleMusicSource.swift   — ScriptingBridge to Music.app
  Sources/ScriptingBridgeProtocols.swift — @objc SB protocol decls
  Coordinator/PlaybackCoordinator.swift  — source selection + unified state
  Window/NotchGeometry.swift  — notch size/position from NSScreen
  Window/NotchWindow.swift    — NSPanel host
  Views/IslandRootView.swift  — hover state container
  Views/CollapsedPill.swift
  Views/ExpandedPlayer.swift
  Views/AudioBars.swift
  Util/ArtworkColor.swift     — dominant color for accent
Tests/NotchIslandTests/
  MockNowPlayingSource.swift
  PlaybackCoordinatorTests.swift
  NotchGeometryTests.swift
Resources/Info.plist
Resources/NotchIsland.entitlements
Makefile                      — build + bundle into .app, run
```

The testable core (models, coordinator, geometry math) is pure Swift and TDD-driven. ScriptingBridge sources and SwiftUI views are integration code verified by compiling and manual run.

---

### Task 1: Project scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/NotchIsland/main.swift`
- Create: `Resources/Info.plist`
- Create: `Resources/NotchIsland.entitlements`
- Create: `Makefile`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchIsland",
            path: "Sources/NotchIsland"
        ),
        .testTarget(
            name: "NotchIslandTests",
            dependencies: ["NotchIsland"],
            path: "Tests/NotchIslandTests"
        )
    ]
)
```

- [ ] **Step 2: Create a placeholder `main.swift`**

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // agent: no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: Create `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NotchIsland</string>
  <key>CFBundleIdentifier</key><string>com.shadycheer.notchisland</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>NotchIsland reads the currently playing track from Spotify and Apple Music and controls playback.</string>
</dict>
</plist>
```

- [ ] **Step 4: Create `Resources/NotchIsland.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.automation.apple-events</key><true/>
</dict>
</plist>
```

- [ ] **Step 5: Create `Makefile`** (builds, packages a minimal `.app`, runs)

```makefile
APP=NotchIsland
BUNDLE=.build/$(APP).app
BIN=.build/release/$(APP)

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force --sign - \
	  --entitlements Resources/NotchIsland.entitlements \
	  $(BUNDLE)/Contents/MacOS/$(APP)

run: bundle
	open $(BUNDLE)

test:
	swift test
```

- [ ] **Step 6: Add a temporary empty `AppDelegate`** so it compiles
  (replaced in Task 9). Create `Sources/NotchIsland/App/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {}
}
```

- [ ] **Step 7: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources Resources Makefile
git commit -m "chore: scaffold NotchIsland Swift package and app bundle"
```

---

### Task 2: Data model

**Files:**
- Create: `Sources/NotchIsland/Model/Track.swift`
- Test: `Tests/NotchIslandTests/PlaybackCoordinatorTests.swift` (model usage covered later)

- [ ] **Step 1: Create the model file**

```swift
import AppKit

enum SourceKind: String, Equatable {
    case spotify
    case appleMusic
}

struct Track: Equatable {
    let id: String          // stable per-track id (player track id or url)
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    var artwork: NSImage?
    var isLiked: Bool?      // nil = source can't report/like

    static func == (l: Track, r: Track) -> Bool {
        l.id == r.id && l.title == r.title && l.artist == r.artist
            && l.album == r.album && l.duration == r.duration
            && l.isLiked == r.isLiked
    }
}

struct PlaybackState: Equatable {
    var isPlaying: Bool
    var position: TimeInterval
    var source: SourceKind
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchIsland/Model/Track.swift
git commit -m "feat: add Track and PlaybackState models"
```

---

### Task 3: NowPlayingSource protocol + Mock

**Files:**
- Create: `Sources/NotchIsland/Sources/NowPlayingSource.swift`
- Create: `Tests/NotchIslandTests/MockNowPlayingSource.swift`

- [ ] **Step 1: Create the protocol**

```swift
import Foundation

protocol NowPlayingSource: AnyObject {
    var kind: SourceKind { get }
    var isRunning: Bool { get }

    /// Snapshot current track, or nil if nothing playing / app not running.
    func currentTrack() -> Track?
    /// Snapshot current playback state, or nil if unavailable.
    func currentState() -> PlaybackState?

    func playPause()
    func next()
    func previous()
    func seek(to position: TimeInterval)

    /// True if this source can set "like". Spotify returns false in v1.
    var canSetLiked: Bool { get }
    func setLiked(_ liked: Bool)
}
```

- [ ] **Step 2: Create the mock (test target)**

```swift
@testable import NotchIsland
import Foundation

final class MockNowPlayingSource: NowPlayingSource {
    let kind: SourceKind
    var isRunning: Bool
    var track: Track?
    var state: PlaybackState?
    var canSetLiked: Bool

    private(set) var playPauseCalls = 0
    private(set) var nextCalls = 0
    private(set) var previousCalls = 0
    private(set) var seekedTo: TimeInterval?
    private(set) var likedSetTo: Bool?

    init(kind: SourceKind, isRunning: Bool = true, canSetLiked: Bool = true) {
        self.kind = kind
        self.isRunning = isRunning
        self.canSetLiked = canSetLiked
    }

    func currentTrack() -> Track? { track }
    func currentState() -> PlaybackState? { state }
    func playPause() { playPauseCalls += 1 }
    func next() { nextCalls += 1 }
    func previous() { previousCalls += 1 }
    func seek(to position: TimeInterval) { seekedTo = position }
    func setLiked(_ liked: Bool) { likedSetTo = liked }
}
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: build succeeds (mock is in test target; run `swift test` to compile it).

Run: `swift test`
Expected: builds, 0 tests run.

- [ ] **Step 4: Commit**

```bash
git add Sources/NotchIsland/Sources/NowPlayingSource.swift Tests/NotchIslandTests/MockNowPlayingSource.swift
git commit -m "feat: add NowPlayingSource protocol and test mock"
```

---

### Task 4: PlaybackCoordinator (TDD)

**Files:**
- Create: `Tests/NotchIslandTests/PlaybackCoordinatorTests.swift`
- Create: `Sources/NotchIsland/Coordinator/PlaybackCoordinator.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@testable import NotchIsland
import XCTest

final class PlaybackCoordinatorTests: XCTestCase {

    private func makeTrack(_ id: String) -> Track {
        Track(id: id, title: "t", artist: "a", album: "al", duration: 100, artwork: nil, isLiked: nil)
    }

    func test_picksTheRunningPlayingSource() {
        let spotify = MockNowPlayingSource(kind: .spotify, isRunning: false)
        let music = MockNowPlayingSource(kind: .appleMusic, isRunning: true)
        music.track = makeTrack("m1")
        music.state = PlaybackState(isPlaying: true, position: 5, source: .appleMusic)

        let c = PlaybackCoordinator(sources: [spotify, music])
        c.refresh()

        XCTAssertEqual(c.track, music.track)
        XCTAssertEqual(c.state?.source, .appleMusic)
    }

    func test_whenBothPlaying_mostRecentlyChangedWins() {
        let spotify = MockNowPlayingSource(kind: .spotify)
        let music = MockNowPlayingSource(kind: .appleMusic)
        spotify.track = makeTrack("s1")
        spotify.state = PlaybackState(isPlaying: true, position: 0, source: .spotify)
        music.track = makeTrack("m1")
        music.state = PlaybackState(isPlaying: true, position: 0, source: .appleMusic)

        let c = PlaybackCoordinator(sources: [spotify, music])
        c.refresh()                          // spotify becomes active (first playing)
        spotify.track = makeTrack("s2")      // spotify changes track most recently
        c.sourceDidSignal(.spotify)
        c.refresh()

        XCTAssertEqual(c.state?.source, .spotify)
    }

    func test_controlsRouteToActiveSource() {
        let music = MockNowPlayingSource(kind: .appleMusic)
        music.track = makeTrack("m1")
        music.state = PlaybackState(isPlaying: true, position: 0, source: .appleMusic)
        let c = PlaybackCoordinator(sources: [music])
        c.refresh()

        c.playPause(); c.next(); c.previous(); c.seek(to: 42); c.toggleLike()

        XCTAssertEqual(music.playPauseCalls, 1)
        XCTAssertEqual(music.nextCalls, 1)
        XCTAssertEqual(music.previousCalls, 1)
        XCTAssertEqual(music.seekedTo, 42)
        XCTAssertEqual(music.likedSetTo, true)
    }

    func test_noSourcePlaying_clearsTrack() {
        let spotify = MockNowPlayingSource(kind: .spotify, isRunning: false)
        let c = PlaybackCoordinator(sources: [spotify])
        c.refresh()
        XCTAssertNil(c.track)
        XCTAssertNil(c.state)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: FAIL — `PlaybackCoordinator` not found.

- [ ] **Step 3: Implement `PlaybackCoordinator`**

```swift
import Observation
import Foundation

@Observable
final class PlaybackCoordinator {
    private(set) var track: Track?
    private(set) var state: PlaybackState?

    @ObservationIgnored private let sources: [NowPlayingSource]
    @ObservationIgnored private var activeKind: SourceKind?

    init(sources: [NowPlayingSource]) {
        self.sources = sources
    }

    /// Called when a source posts a change notification — promotes it so that,
    /// when several are playing, the most recently active wins.
    func sourceDidSignal(_ kind: SourceKind) {
        if let s = source(for: kind), s.isRunning, s.currentState()?.isPlaying == true {
            activeKind = kind
        }
    }

    func refresh() {
        let active = resolveActiveSource()
        activeKind = active?.kind
        if let active, let t = active.currentTrack(), let st = active.currentState() {
            track = t
            state = st
        } else {
            track = nil
            state = nil
        }
    }

    func playPause() { activeSource?.playPause() }
    func next() { activeSource?.next() }
    func previous() { activeSource?.previous() }
    func seek(to position: TimeInterval) { activeSource?.seek(to: position) }

    func toggleLike() {
        guard let s = activeSource, s.canSetLiked else { return }
        let current = track?.isLiked ?? false
        s.setLiked(!current)
        track?.isLiked = !current
    }

    // MARK: - Selection

    private var activeSource: NowPlayingSource? {
        activeKind.flatMap(source(for:))
    }

    private func source(for kind: SourceKind) -> NowPlayingSource? {
        sources.first { $0.kind == kind }
    }

    /// Active source = the sticky activeKind if it is still playing; else the
    /// first running+playing source; else the first running source.
    private func resolveActiveSource() -> NowPlayingSource? {
        if let k = activeKind, let s = source(for: k),
           s.isRunning, s.currentState()?.isPlaying == true {
            return s
        }
        if let playing = sources.first(where: { $0.isRunning && $0.currentState()?.isPlaying == true }) {
            return playing
        }
        return sources.first { $0.isRunning && $0.currentTrack() != nil }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchIsland/Coordinator/PlaybackCoordinator.swift Tests/NotchIslandTests/PlaybackCoordinatorTests.swift
git commit -m "feat: add PlaybackCoordinator with source selection (TDD)"
```

---

### Task 5: ScriptingBridge protocol declarations

**Files:**
- Create: `Sources/NotchIsland/Sources/ScriptingBridgeProtocols.swift`

- [ ] **Step 1: Declare the minimal SB interfaces we use**

```swift
import ScriptingBridge

@objc enum SBPlayerState: Int {
    case stopped = 0x6b505353 // 'kPSS'
    case playing = 0x6b505350 // 'kPSP'
    case paused  = 0x6b505370 // 'kPSp'
}

// Spotify
@objc protocol SpotifyTrack {
    @objc optional var id: String { get }       // spotify uri
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var duration: Int { get }    // milliseconds
    @objc optional var artworkUrl: String { get }
}

@objc protocol SpotifyApplication {
    @objc optional var currentTrack: SpotifyTrack { get }
    @objc optional var playerState: SBPlayerState { get }
    @objc optional var playerPosition: Double { get } // seconds
    @objc optional func playpause()
    @objc optional func nextTrack()
    @objc optional func previousTrack()
    @objc optional func setPlayerPosition(_ position: Double)
    @objc optional var isRunning: Bool { get }
}

// Apple Music (Music.app)
@objc protocol MusicArtwork {
    @objc optional var data: NSImage { get }
}

@objc protocol MusicTrack {
    @objc optional var id: Int { get }
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var duration: Double { get } // seconds
    @objc optional var loved: Bool { get }
    @objc optional func setLoved(_ loved: Bool)
    @objc optional var artworks: [MusicArtwork] { get }
}

@objc protocol MusicApplication {
    @objc optional var currentTrack: MusicTrack { get }
    @objc optional var playerState: SBPlayerState { get }
    @objc optional var playerPosition: Double { get }
    @objc optional func playpause()
    @objc optional func nextTrack()
    @objc optional func previousTrack()
    @objc optional func setPlayerPosition(_ position: Double)
    @objc optional var isRunning: Bool { get }
}

extension SBApplication: SpotifyApplication, MusicApplication, SpotifyTrack, MusicTrack {}
```

> Note: `setPlayerPosition`/`setLoved` map to KVC setters that ScriptingBridge
> proxies. We also use `setValue(_:forKey:)` as a fallback in the sources.

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchIsland/Sources/ScriptingBridgeProtocols.swift
git commit -m "feat: declare ScriptingBridge protocols for Spotify and Music"
```

---

### Task 6: SpotifySource

**Files:**
- Create: `Sources/NotchIsland/Sources/SpotifySource.swift`

- [ ] **Step 1: Implement**

```swift
import ScriptingBridge
import AppKit

final class SpotifySource: NowPlayingSource {
    let kind: SourceKind = .spotify
    let canSetLiked = false   // no local API in v1

    private let bundleID = "com.spotify.client"
    private var app: SpotifyApplication? {
        SBApplication(bundleIdentifier: bundleID) as? SpotifyApplication
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == bundleID }
    }

    func currentTrack() -> Track? {
        guard isRunning, let t = app?.currentTrack, let name = t.name else { return nil }
        let durMs = t.duration ?? 0
        var artwork: NSImage?
        if let urlStr = t.artworkUrl, let url = URL(string: urlStr),
           let data = try? Data(contentsOf: url) {
            artwork = NSImage(data: data)
        }
        return Track(
            id: t.id ?? name,
            title: name,
            artist: t.artist ?? "",
            album: t.album ?? "",
            duration: Double(durMs) / 1000.0,
            artwork: artwork,
            isLiked: nil
        )
    }

    func currentState() -> PlaybackState? {
        guard isRunning, let app else { return nil }
        return PlaybackState(
            isPlaying: app.playerState == .playing,
            position: app.playerPosition ?? 0,
            source: .spotify
        )
    }

    func playPause() { app?.playpause?() }
    func next() { app?.nextTrack?() }
    func previous() { app?.previousTrack?() }
    func seek(to position: TimeInterval) {
        (app as? SBApplication)?.setValue(position, forKey: "playerPosition")
    }
    func setLiked(_ liked: Bool) { /* unsupported in v1 */ }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchIsland/Sources/SpotifySource.swift
git commit -m "feat: add SpotifySource via ScriptingBridge"
```

---

### Task 7: AppleMusicSource

**Files:**
- Create: `Sources/NotchIsland/Sources/AppleMusicSource.swift`

- [ ] **Step 1: Implement**

```swift
import ScriptingBridge
import AppKit

final class AppleMusicSource: NowPlayingSource {
    let kind: SourceKind = .appleMusic
    let canSetLiked = true

    private let bundleID = "com.apple.Music"
    private var app: MusicApplication? {
        SBApplication(bundleIdentifier: bundleID) as? MusicApplication
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == bundleID }
    }

    func currentTrack() -> Track? {
        guard isRunning, let t = app?.currentTrack, let name = t.name else { return nil }
        var artwork: NSImage?
        if let arts = t.artworks, let first = arts.first { artwork = first.data }
        return Track(
            id: t.id.map(String.init) ?? name,
            title: name,
            artist: t.artist ?? "",
            album: t.album ?? "",
            duration: t.duration ?? 0,
            artwork: artwork,
            isLiked: t.loved ?? false
        )
    }

    func currentState() -> PlaybackState? {
        guard isRunning, let app else { return nil }
        return PlaybackState(
            isPlaying: app.playerState == .playing,
            position: app.playerPosition ?? 0,
            source: .appleMusic
        )
    }

    func playPause() { app?.playpause?() }
    func next() { app?.nextTrack?() }
    func previous() { app?.previousTrack?() }
    func seek(to position: TimeInterval) {
        (app as? SBApplication)?.setValue(position, forKey: "playerPosition")
    }
    func setLiked(_ liked: Bool) {
        guard let t = app?.currentTrack as? SBObject else { return }
        t.setValue(liked, forKey: "loved")
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchIsland/Sources/AppleMusicSource.swift
git commit -m "feat: add AppleMusicSource via ScriptingBridge with like support"
```

---

### Task 8: NotchGeometry (TDD)

**Files:**
- Create: `Tests/NotchIslandTests/NotchGeometryTests.swift`
- Create: `Sources/NotchIsland/Window/NotchGeometry.swift`

- [ ] **Step 1: Write failing tests**

```swift
@testable import NotchIsland
import XCTest

final class NotchGeometryTests: XCTestCase {

    func test_notchDisplay_computesCenteredFrameUnderNotch() {
        // screen 1512 wide; notch 200 wide centered; notch 38 tall.
        let g = NotchGeometry.layout(
            screenWidth: 1512, screenTop: 982,
            notchWidth: 200, notchHeight: 38,
            collapsedSize: CGSize(width: 220, height: 32)
        )
        XCTAssertTrue(g.hasNotch)
        // collapsed pill centered horizontally
        XCTAssertEqual(g.collapsedFrame.midX, 756, accuracy: 0.5)
        // sits just under the notch top edge
        XCTAssertEqual(g.collapsedFrame.maxY, 982, accuracy: 0.5)
    }

    func test_noNotch_fallsBackToFloatingCenteredPill() {
        let g = NotchGeometry.layout(
            screenWidth: 1920, screenTop: 1080,
            notchWidth: 0, notchHeight: 0,
            collapsedSize: CGSize(width: 220, height: 32)
        )
        XCTAssertFalse(g.hasNotch)
        XCTAssertEqual(g.collapsedFrame.midX, 960, accuracy: 0.5)
        XCTAssertEqual(g.collapsedFrame.maxY, 1080, accuracy: 0.5)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: FAIL — `NotchGeometry` not found.

- [ ] **Step 3: Implement**

```swift
import CoreGraphics

struct NotchLayout: Equatable {
    let hasNotch: Bool
    let collapsedFrame: CGRect
}

enum NotchGeometry {
    /// Coordinates use a bottom-left origin (AppKit screen space). `screenTop`
    /// is the y of the top edge of the usable area (== screen height here).
    static func layout(
        screenWidth: CGFloat, screenTop: CGFloat,
        notchWidth: CGFloat, notchHeight: CGFloat,
        collapsedSize: CGSize
    ) -> NotchLayout {
        let hasNotch = notchWidth > 0 && notchHeight > 0
        let x = (screenWidth - collapsedSize.width) / 2
        let y = screenTop - collapsedSize.height
        return NotchLayout(
            hasNotch: hasNotch,
            collapsedFrame: CGRect(x: x, y: y, width: collapsedSize.width, height: collapsedSize.height)
        )
    }

    /// Resolve notch dimensions for a screen from AppKit APIs.
    static func notchSize(forScreenWidth width: CGFloat,
                          safeAreaTop: CGFloat,
                          leftArea: CGRect?, rightArea: CGRect?) -> CGSize {
        guard safeAreaTop > 0, let left = leftArea, let right = rightArea else {
            return .zero
        }
        let notchWidth = width - left.width - right.width
        return CGSize(width: max(0, notchWidth), height: safeAreaTop)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS (6 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchIsland/Window/NotchGeometry.swift Tests/NotchIslandTests/NotchGeometryTests.swift
git commit -m "feat: add NotchGeometry layout math (TDD)"
```

---

### Task 9: SwiftUI views

**Files:**
- Create: `Sources/NotchIsland/Views/AudioBars.swift`
- Create: `Sources/NotchIsland/Views/CollapsedPill.swift`
- Create: `Sources/NotchIsland/Views/ExpandedPlayer.swift`
- Create: `Sources/NotchIsland/Views/IslandRootView.swift`
- Create: `Sources/NotchIsland/Util/ArtworkColor.swift`

- [ ] **Step 1: `ArtworkColor.swift` — dominant color**

```swift
import AppKit

enum ArtworkColor {
    static func dominant(_ image: NSImage?) -> NSColor {
        guard let image,
              let tiff = image.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff) else { return .black }
        let w = bmp.pixelsWide, h = bmp.pixelsHigh
        guard w > 0, h > 0 else { return .black }
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        let stepX = max(1, w / 16), stepY = max(1, h / 16)
        for x in stride(from: 0, to: w, by: stepX) {
            for y in stride(from: 0, to: h, by: stepY) {
                if let c = bmp.colorAt(x: x, y: y) {
                    r += c.redComponent; g += c.greenComponent; b += c.blueComponent; n += 1
                }
            }
        }
        guard n > 0 else { return .black }
        return NSColor(red: r/n, green: g/n, blue: b/n, alpha: 1)
    }
}
```

- [ ] **Step 2: `AudioBars.swift`**

```swift
import SwiftUI

struct AudioBars: View {
    var playing: Bool
    @State private var phase = 0.0
    private let timer = Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: barHeight(i))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .onReceive(timer) { _ in if playing { phase += 0.18 } }
    }

    private func barHeight(_ i: Int) -> CGFloat {
        guard playing else { return 4 }
        let v = sin(phase * 3 + Double(i)) * 0.5 + 0.5
        return 4 + v * 10
    }
}
```

- [ ] **Step 3: `CollapsedPill.swift`**

```swift
import SwiftUI

struct CollapsedPill: View {
    let track: Track?
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 8) {
            artwork
            if let title = track?.title {
                Text(title).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white).lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
            }
            Spacer(minLength: 0)
            AudioBars(playing: isPlaying)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.black)
    }

    @ViewBuilder private var artwork: some View {
        if let img = track?.artwork {
            Image(nsImage: img).resizable().frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6).fill(.gray).frame(width: 20, height: 20)
        }
    }
}
```

- [ ] **Step 4: `ExpandedPlayer.swift`**

```swift
import SwiftUI

struct ExpandedPlayer: View {
    let track: Track?
    let state: PlaybackState?
    let canLike: Bool
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrev: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onToggleLike: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(track?.title ?? "Not playing")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(track?.artist ?? "")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    Text(track?.album ?? "")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                }
                Spacer()
                if canLike {
                    Button(action: onToggleLike) {
                        Image(systemName: (track?.isLiked ?? false) ? "heart.fill" : "heart")
                            .foregroundStyle((track?.isLiked ?? false) ? .pink : .white)
                    }.buttonStyle(.plain)
                }
            }
            progress
            transport
        }
        .padding(16)
        .frame(width: 430, height: 200)
        .background(.black)
    }

    @ViewBuilder private var artwork: some View {
        if let img = track?.artwork {
            Image(nsImage: img).resizable().frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12).fill(.gray).frame(width: 74, height: 74)
        }
    }

    private var progress: some View {
        let pos = state?.position ?? 0
        let dur = max(track?.duration ?? 1, 1)
        return VStack(spacing: 4) {
            Slider(value: Binding(
                get: { min(pos / dur, 1) },
                set: { onSeek($0 * dur) }
            )).tint(.white)
            HStack {
                Text(fmt(pos)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(fmt(dur)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 28) {
            Spacer()
            Button(action: onPrev) { Image(systemName: "backward.fill") }.buttonStyle(.plain)
            Button(action: onPlayPause) {
                Image(systemName: (state?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
            }.buttonStyle(.plain)
            Button(action: onNext) { Image(systemName: "forward.fill") }.buttonStyle(.plain)
            Spacer()
        }.foregroundStyle(.white)
    }

    private func fmt(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
```

- [ ] **Step 5: `IslandRootView.swift` — hover state container**

```swift
import SwiftUI

struct IslandRootView: View {
    @State var coordinator: PlaybackCoordinator
    let canLike: Bool
    @State private var expanded = false

    var body: some View {
        Group {
            if expanded {
                ExpandedPlayer(
                    track: coordinator.track,
                    state: coordinator.state,
                    canLike: canLike,
                    onPlayPause: coordinator.playPause,
                    onNext: coordinator.next,
                    onPrev: coordinator.previous,
                    onSeek: coordinator.seek(to:),
                    onToggleLike: coordinator.toggleLike
                )
            } else {
                CollapsedPill(track: coordinator.track,
                              isPlaying: coordinator.state?.isPlaying ?? false)
                    .frame(width: 220)
            }
        }
        .clipShape(.rect(bottomLeadingRadius: 20, bottomTrailingRadius: 20))
        .onHover { hovering in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                expanded = hovering
            }
        }
    }
}
```

- [ ] **Step 6: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/NotchIsland/Views Sources/NotchIsland/Util
git commit -m "feat: add SwiftUI island views (collapsed pill, expanded player)"
```

---

### Task 10: NotchWindow

**Files:**
- Create: `Sources/NotchIsland/Window/NotchWindow.swift`

- [ ] **Step 1: Implement the non-activating panel**

```swift
import AppKit
import SwiftUI

final class NotchWindow: NSPanel {
    init(rootView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        contentView = rootView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Position centered against the notch / top of the given screen.
    func reposition(on screen: NSScreen, size: CGSize) {
        let topLeft = NotchGeometry.notchSize(
            forScreenWidth: screen.frame.width,
            safeAreaTop: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )
        let layout = NotchGeometry.layout(
            screenWidth: screen.frame.width,
            screenTop: screen.frame.maxY,
            notchWidth: topLeft.width,
            notchHeight: topLeft.height,
            collapsedSize: size
        )
        setFrame(CGRect(
            x: screen.frame.minX + layout.collapsedFrame.minX,
            y: layout.collapsedFrame.minY,
            width: max(size.width, 430),
            height: 240
        ), display: true)
    }
}
```

> The window frame is sized to the *expanded* envelope (430×240) so the
> SwiftUI content can grow on hover without clipping; the content view aligns
> to the top so collapsed/expanded both hug the notch.

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchIsland/Window/NotchWindow.swift
git commit -m "feat: add non-activating NotchWindow panel"
```

---

### Task 11: AppDelegate wiring + status item + polling

**Files:**
- Modify: `Sources/NotchIsland/App/AppDelegate.swift`

- [ ] **Step 1: Replace the placeholder with full wiring**

```swift
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
        let root = NSHostingView(rootView:
            IslandRootView(coordinator: coordinator, canLike: canLike)
        )
        root.translatesAutoresizingMaskIntoConstraints = false

        window = NotchWindow(rootView: hostContainer(root))
        if let screen = NSScreen.main {
            window.reposition(on: screen, size: CGSize(width: 220, height: 32))
        }
        window.orderFrontRegardless()

        setupStatusItem()
        observeDistributedNotifications()
        startPolling()
        coordinator.refresh()
    }

    /// Wraps the hosting view pinned to the top of the panel so the island
    /// grows downward from the notch.
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
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Run the full test suite**

Run: `swift test`
Expected: PASS (6 tests).

- [ ] **Step 4: Commit**

```bash
git add Sources/NotchIsland/App/AppDelegate.swift
git commit -m "feat: wire AppDelegate (status item, panel, polling, notifications)"
```

---

### Task 12: Build the bundle and smoke-test on device

**Files:** none (build + manual run)

- [ ] **Step 1: Build and run the bundle**

Run: `make run`
Expected: app launches as a menu-bar agent (music note icon), an island pill
appears under the notch. macOS prompts for Automation permission to control
Spotify / Music on first interaction — grant it.

- [ ] **Step 2: Manual verification checklist**

- Play a track in Spotify → pill shows it; hover → expanded player with art,
  title, artist, album, progress, transport. No heart on Spotify.
- Click play/pause, next, previous → Spotify responds.
- Drag the progress slider → Spotify seeks.
- Play in Apple Music → island switches to it; heart visible; click heart →
  track is loved in Music; progress/transport work.
- Quit Spotify/Music → island idles gracefully.

- [ ] **Step 3: Commit any fixes found during smoke test**

```bash
git add -A
git commit -m "fix: address smoke-test findings"
```

---

## Notes for the implementer

- ScriptingBridge dynamic casts can return nil if the SDEF property names
  differ; if `playerPosition`/`loved` setters don't take, fall back to
  `NSAppleScript` with a literal script (e.g. `tell application "Music" to set
  loved of current track to true`). Keep the protocol-based path primary.
- Artwork fetch for Spotify uses `Data(contentsOf:)` synchronously inside
  `currentTrack()`; if it causes hitching on the 1s tick, move artwork loading
  to a cached async load keyed by track id (fast-follow, not v1-blocking).
- Everything UI/ScriptingBridge is integration-tested by the Task 12 manual
  run. The TDD coverage is the coordinator and geometry, which hold the logic.
