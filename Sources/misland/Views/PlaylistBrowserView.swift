import SwiftUI
import AppKit
import Observation

/// Drives the 2-level playlist browser. Level 1 = the user's playlists; tapping
/// one drills into Level 2 = its songs. All player IPC runs off-main on `queue`.
@Observable
final class PlaylistBrowserModel {
    enum Level: Equatable { case playlists, tracks(PlaylistRef) }

    var level: Level = .playlists
    var playlists: [PlaylistRef] = []
    var tracks: [PlaylistTrackRef] = []
    var loading = false
    var source: SourceKind = .spotify

    /// Per-row enrichment, keyed by row id. Liked drives the heart; cover is a
    /// URL loaded lazily per visible row via ArtworkCache.
    var likedByID: [String: Bool] = [:]
    var coverByID: [String: String] = [:]

    // Playback modes are passthrough — toggling sets the player's mode directly.
    var shuffle = false
    var repeatMode: RepeatMode = .off

    @ObservationIgnored private let queue = DispatchQueue(label: "com.shadycheer.misland.playlist")

    var currentPlaylist: PlaylistRef? {
        if case let .tracks(p) = level { return p }
        return nil
    }

    /// (Re)open at the playlists root for `source` and load it.
    func open(source: SourceKind) {
        self.source = source
        level = .playlists
        tracks = []
        loadPlaylists()
    }

    func loadPlaylists() {
        loading = true
        let src = source
        queue.async {
            let list = PlaylistService.playlists(src)
            let covers = PlaylistService.coverURLs(forPlaylists: list)
            DispatchQueue.main.async {
                guard self.source == src else { return }
                self.playlists = list
                self.coverByID.merge(covers) { _, new in new }
                self.loading = false
            }
        }
    }

    func enter(_ playlist: PlaylistRef) {
        level = .tracks(playlist)
        tracks = []
        loading = true
        queue.async {
            let list = PlaylistService.tracks(in: playlist)
            let liked = PlaylistService.likedStatus(for: list)
            let covers = PlaylistService.coverURLs(for: list)
            DispatchQueue.main.async {
                guard self.currentPlaylist == playlist else { return }
                self.tracks = list
                self.likedByID.merge(liked) { _, new in new }
                self.coverByID.merge(covers) { _, new in new }
                self.loading = false
            }
        }
    }

    func back() { level = .playlists; tracks = [] }

    func isLiked(_ track: PlaylistTrackRef) -> Bool { likedByID[track.id] ?? false }

    func toggleLike(_ track: PlaylistTrackRef) {
        let next = !(likedByID[track.id] ?? false)
        likedByID[track.id] = next                       // optimistic
        let pl = currentPlaylist
        queue.async { PlaylistService.setLiked(next, for: track, in: pl) }
    }

    func play(_ playlist: PlaylistRef) {
        queue.async { PlaylistService.play(playlist: playlist) }
    }

    func play(_ track: PlaylistTrackRef, in playlist: PlaylistRef) {
        queue.async { PlaylistService.play(track: track, in: playlist) }
    }

    func toggleShuffle() {
        shuffle.toggle()
        let on = shuffle, src = source
        queue.async { PlaylistService.setShuffle(on, for: src) }
    }

    func cycleRepeat() {
        repeatMode = repeatMode.next
        let mode = repeatMode, src = source
        queue.async { PlaylistService.setRepeat(mode, for: src) }
    }
}

private extension RepeatMode {
    var next: RepeatMode {
        switch self { case .off: return .all; case .all: return .one; case .one: return .off }
    }
}

struct PlaylistBrowserView: View {
    @State var model: PlaylistBrowserModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.08))
            content
        }
        .frame(width: IslandLayout.expandedWidth, height: IslandLayout.browserHeight, alignment: .top)
    }

    // MARK: Header — back/title + mode controls + close

    private var header: some View {
        HStack(spacing: 12) {
            if case .tracks = model.level {
                IconButton(system: "chevron.left", size: 13) { model.back() }
            } else {
                Image(systemName: sourceIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            IconButton(system: "shuffle", size: 12, tint: model.shuffle ? .green : .white) {
                model.toggleShuffle()
            }
            IconButton(system: repeatIcon, size: 12, tint: model.repeatMode == .off ? .white : .green) {
                model.cycleRepeat()
            }
            // Up-chevron collapses the browser back to the main player panel.
            IconButton(system: "chevron.up", size: 14) { onClose() }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private var title: String {
        switch model.level {
        case .playlists: return model.source == .spotify ? "Spotify 歌单" : "Apple Music 歌单"
        case .tracks(let p): return p.name
        }
    }

    private var sourceIcon: String { "music.note.list" }

    private var repeatIcon: String {
        model.repeatMode == .one ? "repeat.1" : "repeat"
    }

    // MARK: Content — list of playlists or songs

    @ViewBuilder private var content: some View {
        if model.loading {
            VStack { Spacer(); ProgressView().controlSize(.small).tint(.white); Spacer() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    switch model.level {
                    case .playlists:
                        if model.playlists.isEmpty {
                            emptyRow("没有歌单")
                        } else {
                            ForEach(model.playlists) { pl in
                                PlaylistRow(name: pl.name,
                                            coverURL: model.coverByID[pl.id],
                                            onTap: { model.enter(pl) },
                                            onPlay: { model.play(pl) })
                            }
                        }
                    case .tracks(let pl):
                        if model.tracks.isEmpty {
                            emptyRow("空歌单")
                        } else {
                            ForEach(model.tracks) { t in
                                TrackRow(name: t.name, artist: t.artist,
                                         coverURL: model.coverByID[t.id],
                                         liked: model.isLiked(t),
                                         onPlay: { model.play(t, in: pl) },
                                         onToggleLike: { model.toggleLike(t) })
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }
}

// MARK: - Rows

private struct PlaylistRow: View {
    let name: String
    let coverURL: String?
    let onTap: () -> Void
    let onPlay: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            CoverThumb(url: coverURL)
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if hover {
                IconButton(system: "play.fill", size: 11, action: onPlay)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(hover ? Color.white.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hover = $0 }
    }
}

private struct TrackRow: View {
    let name: String
    let artist: String
    let coverURL: String?
    let liked: Bool
    let onPlay: () -> Void
    let onToggleLike: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            CoverThumb(url: coverURL)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1).truncationMode(.tail)
                if !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 6)
            // Heart shows + toggles liked state (no play button — double-click
            // the row to play).
            IconButton(system: liked ? "heart.fill" : "heart", size: 13,
                       tint: liked ? .pink : .white, action: onToggleLike)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(hover ? Color.white.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPlay)
        .onHover { hover = $0 }
    }
}

/// Lazily-loaded square cover for a row. Only fetches when the row appears
/// (scroll-window), and re-uses ArtworkCache so scrolling back is instant.
private struct CoverThumb: View {
    let url: String?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.28))
                    )
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .onAppear(perform: load)
        .onChange(of: url) { _, _ in image = nil; load() }
    }

    private func load() {
        guard image == nil, let url else { return }
        if let cached = ArtworkCache.shared.cached(url) { image = cached; return }
        ArtworkCache.shared.image(for: url) { img in if let img { image = img } }
    }
}

/// Compact header/row button with a hover brighten.
private struct IconButton: View {
    let system: String
    let size: CGFloat
    var tint: Color = .white
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint.opacity(hover ? 1 : 0.7))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
