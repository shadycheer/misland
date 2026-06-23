# MisLand

A native macOS "Dynamic Island" for the music you're playing. MisLand lives in
the MacBook notch (and floats at the top of notch-less / external displays),
showing the current track from **Spotify** and **Apple Music** — collapse it to
a slim pill, hover to expand into a full player.

> 把正在播放的单曲做成 Mac 刘海上的「灵动岛」：封面、歌名、控制、点赞,一应俱全。纯本地、低占用、无需登录授权。

## Features

- **Notch-native island** — a black pill fused to the notch; hover to expand,
  auto-collapse. Falls back to a floating pill on displays without a notch.
- **Spotify + Apple Music** — whichever is playing shows automatically; when
  both play, the most recently active wins.
- **Now playing** — cover, title, artist, album, scrubbable progress.
- **Controls** — previous / play-pause / next, seek.
- **Like ❤️** — add/remove from your library. Apple Music via local scripting;
  Spotify via its bundled `spotify_cli` (no OAuth, no Web-API quota).
- **Click to open** — click the title / artist / album to jump to that page in
  Spotify.
- **Auto-peek** — the island flashes the track info for ~2s when the song
  changes.
- **Share card** — export a clean now-playing card (cover + meta + brand lockup
  + QR) straight to the clipboard.
- **Light** — event-driven with a 0.5s progress tick, players read off the main
  thread; ~2% idle CPU, <50MB RAM.

## Requirements

- macOS 14 (Sonoma) or later — Apple Silicon
- The Spotify and/or Apple Music desktop apps
- Spotify "Like" needs a current Spotify build (uses its bundled `spotify_cli`)

## Install

Download the latest `misland.dmg` from [Releases](../../releases), open it, and
drag **MisLand** to Applications.

The app is ad-hoc signed (not notarized), so the first launch needs a manual
allow: **right-click MisLand → Open → Open**, or System Settings ▸ Privacy &
Security ▸ "Open Anyway". On first playback control, macOS will also ask to
allow Automation for Spotify / Music — click Allow.

Access settings / quit from the menu-bar 🎵 icon, **or right-click the island**
(handy when the menu bar is full and the icon hides behind the notch).

## Build from source

```bash
make run      # build + launch
make watch    # rebuild + relaunch on every save (dev loop)
make test     # unit tests
make dmg      # build a distributable .dmg
```

## How it works

macOS has no Dynamic Island API — the notch is just an inert cutout. MisLand
draws a borderless, non-activating, always-on-top `NSPanel` flush under the
notch; because it's black and rounded it fuses with the hardware notch. A global
mouse monitor toggles click-through so the overlay never blocks the apps below.

Track data comes from each player's local `ScriptingBridge` interface (no
network, no private `MediaRemote` — which Apple locked in macOS 15.4+). Spotify
"Like" and click-to-open use Spotify's bundled `spotify_cli`, which talks to the
already-logged-in desktop app.

## Notes

- Apple Music exposes no public artist/album URLs locally, so click-to-open is
  Spotify-only.
- NetEase Cloud Music / QQ Music can't be supported on macOS 15.4+: no scripting
  interface, `MediaRemote` is locked, and their windows expose no readable
  accessibility tree.
