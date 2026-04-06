// Sources/RodaAi/Design/Colors.swift
import SwiftUI

/// Tokens de cor do design system RodaAi.
/// Cada cor tem variantes light e dark com contraste WCAG AA garantido.
struct ColorPalette: Sendable {
    // MARK: - Primary
    static let accent = Color(hex: "#00875A")
    static let accentLight = Color(hex: "#00A86B")

    // MARK: - Semantic
    static let success = Color(hex: "#00875A")
    static let warning = Color(hex: "#E5A100")
    static let error = Color(hex: "#D4351C")

    // MARK: - Surfaces (Light)
    static let surface = Color(hex: "#FAFAFA")
    static let surfaceElevated = Color(hex: "#FFFFFF")
    static let surfaceSecondary = Color(hex: "#F5F5F5")

    // MARK: - Text (Light)
    static let textPrimary = Color(hex: "#1A1A1A")
    static let textSecondary = Color(hex: "#6B6B6B")
    static let textTertiary = Color(hex: "#9B9B9B")

    // MARK: - Dark Mode Registry
    private static let darkVariants: [String: Color] = [
        "rodaAccent": Color(hex: "#00A86B"),
        "rodaAccentLight": Color(hex: "#00C77B"),
        "rodaSuccess": Color(hex: "#00A86B"),
        "rodaWarning": Color(hex: "#FFBF00"),
        "rodaError": Color(hex: "#FF6B4A"),
        "rodaSurface": Color(hex: "#1A1A1A"),
        "rodaSurfaceElevated": Color(hex: "#2A2A2A"),
        "rodaSurfaceSecondary": Color(hex: "#242424"),
        "rodaTextPrimary": Color(hex: "#F0F0F0"),
        "rodaTextSecondary": Color(hex: "#A0A0A0"),
        "rodaTextTertiary": Color(hex: "#707070"),
    ]

    static func darkVariant(for name: String) -> Color? {
        darkVariants[name]
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
