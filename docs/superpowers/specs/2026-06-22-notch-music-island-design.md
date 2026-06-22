# Notch Music Island — Design (v1)

Date: 2026-06-22
Status: Approved (pending spec review)

## Summary

A native macOS app that lives in the menu bar and renders the currently
playing track from Spotify and Apple Music as a notch-fused "Dynamic
Island"-style overlay. Collapsed, it is a small pill hugging the bottom of
the hardware notch. On hover it expands into a player showing album art,
title, artist, album, a scrubbable progress bar with times, transport
controls (previous / play-pause / next), and a like button.

The visual quality bar is [vibeisland.app](https://vibeisland.app) — which is
actually an AI-agent monitor, not a music app, but established the notch-island
form factor we are matching: pure Swift, non-activating overlay, <50MB RAM,
near-zero idle CPU, fully local, notch on built-in displays with a floating
fallback elsewhere.

## Key technical reality (why these choices)

- macOS has **no Dynamic Island API** (unlike iOS). The hardware notch is an
  inert black cutout. The "island" is an illusion: a borderless, black,
  always-on-top, non-activating `NSPanel` drawn flush against the bottom edge
  of the notch. Because it is black and rounded, it fuses with the hardware
  notch and appears to "grow." All content renders in this overlay, below the
  camera cutout.
- On macOS 15.4+ (this machine: 26.5) the private `MediaRemote` framework that
  exposed system-wide now-playing is **locked** for third-party apps. So we do
  not read global now-playing; we talk to each player directly.
- **Spotify** and **Apple Music** both expose `ScriptingBridge` (AppleScript)
  interfaces locally — track metadata, artwork, position, player state, and
  transport control. No network, no rate limits.
- **NetEase Cloud Music (网易云)** has no usable scripting interface on 26.5 and
  MediaRemote is locked, so it would require Accessibility (AX) screen-scraping
  — fragile, no precise progress. Deferred to v2.
- **Lyrics** are not in any local player interface; they require a network
  source (NetEase lyric API). Deferred to v2.

## Scope

### v1 (this spec)
- Players: **Spotify** + **Apple Music** via ScriptingBridge.
- Display: album art, title, artist, album, progress + duration.
- Control: previous / play-pause / next, scrubbable (seek) progress.
- Like: Apple Music only (set `loved`/favorite locally). Hidden on Spotify.
- Notch-fused overlay on built-in notch displays; centered floating pill
  fallback on non-notch displays / external monitors.
- Menu bar item: quit, preferences, launch-at-login.

### v2 (out of scope here)
- NetEase Cloud Music via Accessibility screen-scraping.
- Lyrics (NetEase lyric API, line- and word-level timing) in the expanded view.
- Spotify like via optional Spotify Web API (OAuth) login.

## Architecture

Units are small and independently testable, communicating through
well-defined interfaces.

### 1. `NowPlayingSource` (protocol)
The abstraction every player implementation conforms to.
- Publishes the current `Track` and `PlaybackState`.
- Control methods: `playPause()`, `next()`, `previous()`, `seek(to:)`,
  `setLiked(_:)` (optional; nil-capability for sources that can't).
- Exposes a `isRunning` / availability signal.

Implementations:
- **`SpotifySource`** — ScriptingBridge to `Spotify.app`. Reads
  `current track` (name, artist, album, `duration`, `artwork url`),
  `player position`, `player state`. Controls via `playpause`, `next track`,
  `previous track`, and sets `player position` for seek. `setLiked` reports
  unsupported (no local API).
- **`AppleMusicSource`** — ScriptingBridge to `Music.app`. Reads
  `current track` (name, artist, album, `duration`, `artworks` raw image),
  `player position`, `player state`. Controls via `playpause`, `next track`,
  `previous track`, set `player position`. `setLiked` sets `loved`/favorite
  on the current track.

### 2. `PlaybackCoordinator`
- Selects the active source: whichever player is currently playing; if both
  are playing, the most-recently-active wins; if none, the last one that was.
- Event-driven via `DistributedNotificationCenter`
  (`com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo`),
  plus a light progress tick (1s) only while playing or while the overlay is
  expanded.
- Publishes a unified `Track` + `PlaybackState` via `@Observable` for SwiftUI.
- Debounces rapid track changes.

### 3. `NotchWindow`
- Borderless, non-activating (`.nonactivatingPanel`), always-on-top
  (`.statusBar`/`.mainMenu`-level) `NSPanel`; transparent background; black,
  rounded content.
- Computes notch geometry from `NSScreen.safeAreaInsets.top` (height) and
  `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (width + center) to align
  flush under the notch.
- Falls back to a centered floating pill on displays without a notch.
- v1 follows the main screen; multi-display follow is a fast-follow, not a
  blocker.
- Hosts the SwiftUI content via `NSHostingView`.

### 4. SwiftUI views
- `CollapsedPill` — mini artwork + animated audio bars + (truncated) title,
  sized to hug the notch.
- `ExpandedPlayer` — large artwork, title/artist/album, scrubbable progress
  bar with current/total time, transport (prev / play-pause / next), like.
- Hover-driven expand/collapse with a spring animation (mouseenter expands,
  mouseleave collapses).
- Optional accent glow derived from the artwork's dominant color.

### 5. Menu bar `NSStatusItem`
- Quit, Preferences, Launch at login (off by default).

## Data model
- `Track { id, title, artist, album, artwork: NSImage?, duration: TimeInterval, isLiked: Bool? }`
- `PlaybackState { isPlaying: Bool, position: TimeInterval, source: SourceKind }`

## Behavior details
- **Artwork**: Apple Music yields raw image data locally. Spotify yields an
  `artwork url` fetched once per track change (benign single image GET, not a
  rate-limited API).
- **Like**: Apple Music sets `loved`. Spotify hides the button in v1.
- **Control**: ScriptingBridge drives play/pause, next/previous, and seek on
  both players.

## Error handling & edges
- Player not running / no current track → island idles (hidden or minimal).
- First control/read triggers macOS Automation (AppleEvents) permission;
  requires `NSAppleEventsUsageDescription`. Denial is handled gracefully with a
  prompt explaining how to grant it in System Settings.
- Non-notch displays and external monitors → floating fallback.
- Track-change debounce to avoid flicker.

## Performance
- Event-driven (DistributedNotifications) with progress polling only while
  playing or expanded. Target: <50MB RAM, near-zero idle CPU, matching the
  vibeisland bar.

## Testing
- Protocol-based sources allow a `MockNowPlayingSource` for unit-testing
  `PlaybackCoordinator` (source selection, play/pause/track-change state
  transitions). TDD for this logic.
- Overlay geometry and visuals verified manually / via snapshots.

## Build
- Pure Swift / SwiftUI, Apple Silicon native. Requires macOS + Xcode.
