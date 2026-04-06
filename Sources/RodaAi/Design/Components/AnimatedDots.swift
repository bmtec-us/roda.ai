// Sources/RodaAi/Design/Components/AnimatedDots.swift
import SwiftUI

struct AnimatedDots: View {
    let reduceMotion: Bool
    let dotCount = 3

    var isStatic: Bool { reduceMotion }

    init(reduceMotion: Bool = false) {
        self.reduceMotion = reduceMotion
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(ColorPalette.textSecondary)
                    .frame(width: 6, height: 6)
                    .opacity(reduceMotion ? 1.0 : 0.3)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: reduceMotion
                    )
            }
        }
    }
}
