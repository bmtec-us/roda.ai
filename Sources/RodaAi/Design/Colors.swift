// Sources/RodaAi/Design/Colors.swift
//
// Design tokens para Liquid Glass (iOS 26+).
//
// Principio: usar cores SEMANTICAS do SwiftUI que se adaptam automaticamente
// a materiais glass, dark mode, e acessibilidade. Cores hardcoded (hex)
// nao refratam corretamente em superficies glass e parecem "flat".
//
// Ref: Apple HIG "Color and Materials" — Liquid Glass design language.
import SwiftUI

struct ColorPalette: Sendable {
    // MARK: - Brand Accent
    /// Accent primario do app. Usado como .tint() no root e propagado para glass.
    static let accent = Color.green  // Maps to SF Green, adapts to glass

    // MARK: - Semantic
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red

    // MARK: - Text (Semantic — adapts to glass & dark mode automatically)
    static let textPrimary: Color = .primary
    static let textSecondary: Color = .secondary
    static let textTertiary = Color.secondary.opacity(0.7)

    // MARK: - Surfaces (Semantic Materials)
    // No Liquid Glass, nao usamos cores de fundo opacas.
    // Usamos Materials do SwiftUI que se adaptam ao glass.
    static let surface = Color(.systemBackground)
    static let surfaceElevated = Color(.secondarySystemBackground)
    static let surfaceSecondary = Color(.tertiarySystemBackground)

    // MARK: - Legacy compat
    static let accentLight = Color.green.opacity(0.85)
}
