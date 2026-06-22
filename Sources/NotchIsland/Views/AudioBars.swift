import SwiftUI

struct AudioBars: View {
    var playing: Bool

    private let count = 4
    private let phase: [Double] = [0.0, 1.3, 2.4, 0.7] // desync the bars
    private let minH: CGFloat = 4
    private let maxH: CGFloat = 15

    var body: some View {
        Group {
            if playing {
                // .animation drives at the display refresh rate → genuinely
                // smooth, unlike a low-frequency Timer.
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    bars { i in
                        let v = (sin(t * 7 + phase[i]) + 1) / 2   // 0…1
                        return minH + CGFloat(v) * (maxH - minH)
                    }
                }
            } else {
                bars { [7, 12, 6, 10][$0 % 4] } // resting equalizer
            }
        }
        .frame(height: maxH, alignment: .bottom)
    }

    private func bars(_ height: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(.white).frame(width: 3, height: height(i))
            }
        }
    }
}
