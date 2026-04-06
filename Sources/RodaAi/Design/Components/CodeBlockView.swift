// Sources/RodaAi/Design/Components/CodeBlockView.swift
import SwiftUI

struct CodeBlockView: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language {
                HStack {
                    Text(language)
                        .font(.rodaCaption)
                        .foregroundStyle(ColorPalette.textSecondary)
                    Spacer()
                    Button("common.copy") {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = code
                        #elseif canImport(AppKit)
                        NSPasteboard.general.setString(code, forType: .string)
                        #endif
                    }
                    .font(.rodaCaption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ColorPalette.surfaceSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.rodaCode)
                    .foregroundStyle(ColorPalette.textPrimary)
                    .padding(12)
            }
        }
        .background(ColorPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
