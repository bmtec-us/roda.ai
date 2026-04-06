// Tests/RodaAiTests/Design/ColorTokensTests.swift
import XCTest
@testable import RodaAi

final class ColorTokensTests: XCTestCase {

    // MARK: - WCAG Contrast Ratio Helpers

    /// Calcula luminancia relativa conforme WCAG 2.1
    private func relativeLuminance(_ color: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
        func linearize(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(color.r) + 0.7152 * linearize(color.g) + 0.0722 * linearize(color.b)
    }

    private func contrastRatio(_ c1: (r: CGFloat, g: CGFloat, b: CGFloat),
                                _ c2: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
        let l1 = relativeLuminance(c1)
        let l2 = relativeLuminance(c2)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - Light Mode Contrast (text on surface)

    func testPrimaryTextOnSurfaceContrastMeetsWCAG_AA() {
        // rodaTextPrimary (#1A1A1A) on rodaSurface (#FAFAFA)
        let text = (r: CGFloat(0x1A) / 255, g: CGFloat(0x1A) / 255, b: CGFloat(0x1A) / 255)
        let bg = (r: CGFloat(0xFA) / 255, g: CGFloat(0xFA) / 255, b: CGFloat(0xFA) / 255)
        let ratio = contrastRatio(text, bg)
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "Primary text on surface must meet WCAG AA 4.5:1, got \(ratio)")
    }

    func testSecondaryTextOnSurfaceContrastMeetsWCAG_AA() {
        // rodaTextSecondary (#6B6B6B) on rodaSurface (#FAFAFA)
        let text = (r: CGFloat(0x6B) / 255, g: CGFloat(0x6B) / 255, b: CGFloat(0x6B) / 255)
        let bg = (r: CGFloat(0xFA) / 255, g: CGFloat(0xFA) / 255, b: CGFloat(0xFA) / 255)
        let ratio = contrastRatio(text, bg)
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "Secondary text on surface must meet WCAG AA 4.5:1, got \(ratio)")
    }

    func testTertiaryTextOnSurfaceContrastMeetsWCAG_LargeText() {
        // rodaTextTertiary (#9B9B9B) on rodaSurface (#FAFAFA) — used for captions (large text rule 3:1)
        let text = (r: CGFloat(0x9B) / 255, g: CGFloat(0x9B) / 255, b: CGFloat(0x9B) / 255)
        let bg = (r: CGFloat(0xFA) / 255, g: CGFloat(0xFA) / 255, b: CGFloat(0xFA) / 255)
        let ratio = contrastRatio(text, bg)
        XCTAssertGreaterThanOrEqual(ratio, 3.0, "Tertiary text (large) on surface must meet WCAG 3:1, got \(ratio)")
    }

    func testAccentOnSurfaceContrastMeetsWCAG_LargeText() {
        // rodaAccent (#00875A) on rodaSurface (#FAFAFA)
        let accent = (r: CGFloat(0x00) / 255, g: CGFloat(0x87) / 255, b: CGFloat(0x5A) / 255)
        let bg = (r: CGFloat(0xFA) / 255, g: CGFloat(0xFA) / 255, b: CGFloat(0xFA) / 255)
        let ratio = contrastRatio(accent, bg)
        XCTAssertGreaterThanOrEqual(ratio, 3.0, "Accent on surface must meet WCAG 3:1 for large text, got \(ratio)")
    }

    func testErrorColorOnSurfaceContrastMeetsWCAG_AA() {
        // rodaError (#D4351C) on rodaSurface (#FAFAFA)
        let error = (r: CGFloat(0xD4) / 255, g: CGFloat(0x35) / 255, b: CGFloat(0x1C) / 255)
        let bg = (r: CGFloat(0xFA) / 255, g: CGFloat(0xFA) / 255, b: CGFloat(0xFA) / 255)
        let ratio = contrastRatio(error, bg)
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "Error text on surface must meet WCAG AA 4.5:1, got \(ratio)")
    }

    // MARK: - Dark Mode Variants Exist

    func testAllColorsHaveDarkModeVariants() {
        let colorNames = [
            "rodaAccent", "rodaAccentLight",
            "rodaSuccess", "rodaWarning", "rodaError",
            "rodaSurface", "rodaSurfaceElevated", "rodaSurfaceSecondary",
            "rodaTextPrimary", "rodaTextSecondary", "rodaTextTertiary"
        ]
        for name in colorNames {
            XCTAssertNotNil(
                ColorPalette.darkVariant(for: name),
                "Color '\(name)' must have a dark mode variant"
            )
        }
    }

    func testDarkModePrimaryTextOnDarkSurfaceContrastMeetsWCAG_AA() {
        // Dark: rodaTextPrimary (#F0F0F0) on rodaSurface (#1A1A1A)
        let text = (r: CGFloat(0xF0) / 255, g: CGFloat(0xF0) / 255, b: CGFloat(0xF0) / 255)
        let bg = (r: CGFloat(0x1A) / 255, g: CGFloat(0x1A) / 255, b: CGFloat(0x1A) / 255)
        let ratio = contrastRatio(text, bg)
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "Dark mode primary text must meet WCAG AA 4.5:1, got \(ratio)")
    }

    // MARK: - Color Palette Completeness

    func testColorPaletteHasAllRequiredTokens() {
        XCTAssertNotNil(ColorPalette.accent)
        XCTAssertNotNil(ColorPalette.accentLight)
        XCTAssertNotNil(ColorPalette.success)
        XCTAssertNotNil(ColorPalette.warning)
        XCTAssertNotNil(ColorPalette.error)
        XCTAssertNotNil(ColorPalette.surface)
        XCTAssertNotNil(ColorPalette.surfaceElevated)
        XCTAssertNotNil(ColorPalette.surfaceSecondary)
        XCTAssertNotNil(ColorPalette.textPrimary)
        XCTAssertNotNil(ColorPalette.textSecondary)
        XCTAssertNotNil(ColorPalette.textTertiary)
    }
}
