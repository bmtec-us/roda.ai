// Sources/RodaAi/Design/Components/GlassCard.swift
import SwiftUI

struct GlassCard<Content: View>: View {
    static var cornerRadius: CGFloat { 16 }
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}
