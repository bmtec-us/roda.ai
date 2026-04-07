// Sources/RodaAi/Design/Components/ErrorBanner.swift
import SwiftUI

struct ErrorBanner: View {
    let message: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var iconColor: Color = .orange
    var onRetry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .font(.body)
                .accessibilityHidden(true)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let onRetry {
                Button("chat.action.retry") {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("common.cancel")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(iconColor.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .transition(reduceMotion
            ? .opacity
            : .move(edge: .top).combined(with: .opacity))
    }
}
