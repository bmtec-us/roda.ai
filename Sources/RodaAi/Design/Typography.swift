// Sources/RodaAi/Design/Typography.swift
import SwiftUI

extension Font {
    /// Titulo principal — largeTitle, bold
    static let rodaTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    /// Subtitulos e secoes — headline, semibold
    static let rodaHeadline = Font.system(.headline, design: .default, weight: .semibold)
    /// Corpo de texto — body, regular
    static let rodaBody = Font.system(.body, design: .default)
    /// Legendas e metadata — caption, regular
    static let rodaCaption = Font.system(.caption, design: .default)
    /// Blocos de codigo — body, monospaced
    static let rodaCode = Font.system(.body, design: .monospaced)
}
