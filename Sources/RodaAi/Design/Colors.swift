// Sources/RodaAi/Design/Colors.swift
//
// Design tokens para Liquid Glass (iOS 26+).
//
// Principio: usar cores semanticas com variantes light/dark para manter
// superficies suaves (pastel) sem branco puro.
import SwiftUI

struct ColorPalette: Sendable {
    #if os(iOS)
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }
    #elseif os(macOS)
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil) { appearance in
            guard let appearance else { return light }
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    #endif

    // MARK: - Brand Accent
    #if os(iOS)
    static let accent = dynamic(
        light: UIColor(red: 0.36, green: 0.62, blue: 0.88, alpha: 1.0),
        dark: UIColor(red: 0.52, green: 0.73, blue: 0.95, alpha: 1.0)
    )
    #elseif os(macOS)
    static let accent = dynamic(
        light: NSColor(red: 0.36, green: 0.62, blue: 0.88, alpha: 1.0),
        dark: NSColor(red: 0.52, green: 0.73, blue: 0.95, alpha: 1.0)
    )
    #endif

    // MARK: - Semantic
    #if os(iOS)
    static let success = dynamic(
        light: UIColor(red: 0.49, green: 0.76, blue: 0.67, alpha: 1.0),
        dark: UIColor(red: 0.58, green: 0.83, blue: 0.74, alpha: 1.0)
    )
    static let warning = dynamic(
        light: UIColor(red: 0.93, green: 0.72, blue: 0.53, alpha: 1.0),
        dark: UIColor(red: 0.96, green: 0.79, blue: 0.62, alpha: 1.0)
    )
    static let error = dynamic(
        light: UIColor(red: 0.88, green: 0.52, blue: 0.55, alpha: 1.0),
        dark: UIColor(red: 0.93, green: 0.64, blue: 0.66, alpha: 1.0)
    )
    #elseif os(macOS)
    static let success = dynamic(
        light: NSColor(red: 0.49, green: 0.76, blue: 0.67, alpha: 1.0),
        dark: NSColor(red: 0.58, green: 0.83, blue: 0.74, alpha: 1.0)
    )
    static let warning = dynamic(
        light: NSColor(red: 0.93, green: 0.72, blue: 0.53, alpha: 1.0),
        dark: NSColor(red: 0.96, green: 0.79, blue: 0.62, alpha: 1.0)
    )
    static let error = dynamic(
        light: NSColor(red: 0.88, green: 0.52, blue: 0.55, alpha: 1.0),
        dark: NSColor(red: 0.93, green: 0.64, blue: 0.66, alpha: 1.0)
    )
    #endif

    // MARK: - Text
    static let textPrimary: Color = .primary
    static let textSecondary: Color = .secondary
    static let textTertiary = Color.secondary.opacity(0.7)

    // MARK: - Surfaces
    #if os(iOS)
    static let surface = dynamic(
        light: UIColor(red: 0.96, green: 0.98, blue: 0.99, alpha: 1.0), // ice white
        dark: UIColor(red: 0.09, green: 0.11, blue: 0.14, alpha: 1.0)
    )
    static let surfaceElevated = dynamic(
        light: UIColor(red: 0.92, green: 0.95, blue: 0.97, alpha: 1.0),
        dark: UIColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1.0)
    )
    static let surfaceSecondary = dynamic(
        light: UIColor(red: 0.88, green: 0.92, blue: 0.95, alpha: 1.0),
        dark: UIColor(red: 0.18, green: 0.21, blue: 0.25, alpha: 1.0)
    )
    #elseif os(macOS)
    static let surface = dynamic(
        light: NSColor(red: 0.96, green: 0.98, blue: 0.99, alpha: 1.0),
        dark: NSColor(red: 0.09, green: 0.11, blue: 0.14, alpha: 1.0)
    )
    static let surfaceElevated = dynamic(
        light: NSColor(red: 0.92, green: 0.95, blue: 0.97, alpha: 1.0),
        dark: NSColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1.0)
    )
    static let surfaceSecondary = dynamic(
        light: NSColor(red: 0.88, green: 0.92, blue: 0.95, alpha: 1.0),
        dark: NSColor(red: 0.18, green: 0.21, blue: 0.25, alpha: 1.0)
    )
    #endif

    // MARK: - Legacy compat
    static let accentLight = accent.opacity(0.85)
}
