import AppKit
import Observation
import SwiftUI

@Observable
final class HistoryBrowserModel {
    var entries: [PlaybackHistoryEntry] = []

    @ObservationIgnored private let queue = DispatchQueue(label: "com.shadycheer.misland.history")

    func open() {
        entries = PlaybackHistoryStore.shared.entries()
    }

    func replay(_ entry: PlaybackHistoryEntry) {
        guard entry.canReplay else { return }
        queue.async { PlaybackHistoryStore.shared.replay(entry) }
    }

    func openLink(_ entry: PlaybackHistoryEntry) {
        queue.async { PlaybackHistoryStore.shared.openLink(entry) }
    }

    func clear() {
        PlaybackHistoryStore.shared.clear()
        entries = []
    }
}

struct HistoryBrowserView: View {
    @State var model: HistoryBrowserModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(.white.opacity(0.08))
                .frame(width: IslandLayout.expandedContentWidth)
            content
        }
        .frame(width: IslandLayout.expandedWidth, height: IslandLayout.browserHeight, alignment: .top)
        .onAppear { model.open() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))

            Text("播放历史")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 6)

            if !model.entries.isEmpty {
                IconButton(system: "trash", size: 12, tint: .white) {
                    model.clear()
                }
            }
            IconButton(system: "chevron.up", size: 14) { onClose() }
        }
        .frame(width: IslandLayout.expandedContentWidth)
        .frame(height: 40)
    }

    @ViewBuilder private var content: some View {
        if model.entries.isEmpty {
            Text("还没有播放历史")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.entries) { entry in
                        HistoryRow(
                            entry: entry,
                            onReplay: { model.replay(entry) },
                            onOpen: { model.openLink(entry) }
                        )
                    }
                }
                .padding(.vertical, 4)
                .frame(width: IslandLayout.expandedContentWidth)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: PlaybackHistoryEntry
    let onReplay: () -> Void
    let onOpen: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            sourceThumb
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    sourceBadge
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            Text(relativeTime)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.32))
                .monospacedDigit()
            if entry.trackLink != nil {
                IconButton(system: "arrow.up.forward", size: 11, action: onOpen)
            }
            if entry.canReplay {
                IconButton(system: "play.fill", size: 11, action: onReplay)
            }
        }
        .frame(height: 44)
        .frame(width: IslandLayout.expandedContentWidth)
        .background(hover ? Color.white.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard entry.canReplay else { return }
            onReplay()
        }
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var sourceThumb: some View {
        Group {
            if let image = historyArtwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(sourceColor.opacity(0.18))
                    .overlay(
                        Image(systemName: sourceIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(sourceColor)
                    )
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var historyArtwork: NSImage? {
        guard let path = entry.artworkPath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private var sourceBadge: some View {
        Text(sourceName)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(sourceColor)
            .padding(.horizontal, 5)
            .frame(height: 15)
            .background(sourceColor.opacity(0.16), in: Capsule())
    }

    private var subtitle: String {
        [entry.artist, entry.album].filter { !$0.isEmpty }.joined(separator: " - ")
    }

    private var sourceName: String {
        switch entry.source {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple"
        case .qqMusic: return "QQ"
        case .neteaseMusic: return "网易云"
        }
    }

    private var sourceIcon: String {
        switch entry.source {
        case .spotify: return "music.note"
        case .appleMusic: return "music.note"
        case .qqMusic: return "q.circle"
        case .neteaseMusic: return "music.quarternote.3"
        }
    }

    private var sourceColor: Color {
        switch entry.source {
        case .spotify: return .green
        case .appleMusic: return .pink
        case .qqMusic: return .yellow
        case .neteaseMusic: return .red
        }
    }

    private var relativeTime: String {
        let seconds = max(0, Int(Date().timeIntervalSince(entry.playedAt)))
        if seconds < 60 { return "刚刚" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

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
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
