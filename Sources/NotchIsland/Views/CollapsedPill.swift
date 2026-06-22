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
