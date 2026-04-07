// Sources/RodaAi/Design/Components/GlassCard.swift
import SwiftUI

/// Card com efeito Liquid Glass (iOS 26+) ou material translucido (fallback).
struct GlassCard<Content: View>: View {
    static var cornerRadius: CGFloat { 20 }
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .modifier(GlassBackgroundModifier(cornerRadius: Self.cornerRadius))
    }
}

/// Aplica .glassEffect() no iOS 26+ ou .ultraThinMaterial como fallback.
private struct GlassBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content
                .glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
    }
}
