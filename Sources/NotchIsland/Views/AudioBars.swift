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
        guard playing else {
            // Static "resting equalizer" so paused state isn't four flat dots.
            return [7, 12, 6, 10][i % 4]
        }
        let v = sin(phase * 3 + Double(i)) * 0.5 + 0.5
        return 4 + v * 10
    }
}
