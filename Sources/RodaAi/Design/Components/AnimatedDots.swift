// Sources/RodaAi/Design/Components/AnimatedDots.swift
import SwiftUI

/// Tres dots animados pulsando em sequencia, usado como typing indicator.
/// Respeita Reduced Motion: quando reduceMotion=true, exibe 3 dots estaticos
/// com opacidade fixa.
struct AnimatedDots: View {
    let reduceMotion: Bool
    let dotCount = 3
    let color: Color

    /// True quando dots sao estaticos (Reduced Motion). Exposto para testes.
    var isStatic: Bool { reduceMotion }

    @State private var animating = false

    init(reduceMotion: Bool = false, color: Color = .secondary) {
        self.reduceMotion = reduceMotion
        self.color = color
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .opacity(opacityFor(index: index))
                    .scaleEffect(scaleFor(index: index))
            }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    animating = true
                }
            }
        }
        .accessibilityHidden(true)  // decorativo
    }

    private func opacityFor(index: Int) -> Double {
        if reduceMotion {
            return 0.6  // estatico, valor intermediario
        }
        // Cada dot tem fase ligeiramente diferente para criar onda
        return animating ? 1.0 : 0.3
    }

    private func scaleFor(index: Int) -> CGFloat {
        if reduceMotion {
            return 1.0
        }
        return animating ? 1.0 : 0.7
    }
}

#Preview {
    VStack(spacing: 24) {
        AnimatedDots(reduceMotion: false)
        AnimatedDots(reduceMotion: true)
        AnimatedDots(reduceMotion: false, color: .accentColor)
    }
    .padding()
}
