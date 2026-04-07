// Sources/RodaAi/Features/Voice/VoiceWaveform.swift
import SwiftUI

struct VoiceWaveform: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        if reduceMotion || !isActive {
            // Static representation for Reduced Motion or inactive state
            HStack(spacing: 3) {
                ForEach(0..<20, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 3, height: isActive ? CGFloat.random(in: 8...30) : 8)
                }
            }
        } else {
            // Animated waveform using TimelineView
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    let midY = size.height / 2
                    let barWidth: CGFloat = 3
                    let spacing: CGFloat = 3
                    let totalWidth = barWidth + spacing
                    let barCount = Int(size.width / totalWidth)

                    let date = timeline.date.timeIntervalSinceReferenceDate

                    for i in 0..<barCount {
                        let x = CGFloat(i) * totalWidth
                        let normalizedX = CGFloat(i) / CGFloat(barCount)
                        let amplitude = sin(normalizedX * .pi * 4 + date * 3) * 0.5 + 0.5
                        let height = max(4, amplitude * size.height * 0.8)

                        let rect = CGRect(
                            x: x,
                            y: midY - height / 2,
                            width: barWidth,
                            height: height
                        )
                        let path = Path(roundedRect: rect, cornerRadius: 1.5)
                        context.fill(path, with: .color(Color.accentColor))
                    }
                }
            }
        }
    }
}
