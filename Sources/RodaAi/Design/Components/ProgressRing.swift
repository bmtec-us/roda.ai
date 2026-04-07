// Sources/RodaAi/Design/Components/ProgressRing.swift
import SwiftUI

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 6

    var clampedProgress: Double {
        min(max(progress, 0.0), 1.0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: clampedProgress)
        }
    }
}
