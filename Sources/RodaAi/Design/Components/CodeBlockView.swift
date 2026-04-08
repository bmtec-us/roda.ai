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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("common.copy") {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = code
                        #elseif canImport(AppKit)
                        NSPasteboard.general.setString(code, forType: .string)
                        #endif
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        // Solid tertiary fill reads more reliably than `.glass(.clear)` on
        // the app's ice-white light-mode surface. Code blocks need to feel
        // like a distinct surface, which a near-transparent glass can't do.
        .background(.tertiary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
