// Sources/RodaAi/Design/Components/ErrorBanner.swift
//
// Componente reutilizavel para exibir erros nao-fatais com opcao de retry
// e dismiss. Substitui o HStack inline ad-hoc usado em ChatView/ModelGallery.
//
// Visual: ultraThinMaterial background, warning icon, label, optional buttons.
// Slide-down animation respeita @Environment(\.accessibilityReduceMotion).
import SwiftUI

struct ErrorBanner: View {
    let message: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var iconColor: Color = ColorPalette.warning
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
                .font(.rodaCaption)
                .foregroundStyle(ColorPalette.textPrimary)
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

#Preview("Error with retry + dismiss") {
    VStack(spacing: 20) {
        ErrorBanner(
            message: "Memoria insuficiente. Necessario: 8GB, disponivel: 4GB",
            onRetry: { print("retry") },
            onDismiss: { print("dismiss") }
        )

        ErrorBanner(
            message: "Erro ao baixar modelo. Verifique sua conexao.",
            systemImage: "wifi.slash",
            iconColor: ColorPalette.error,
            onRetry: { print("retry") }
        )

        ErrorBanner(
            message: "Modelo carregado com sucesso",
            systemImage: "checkmark.circle.fill",
            iconColor: ColorPalette.accent
        )
    }
    .padding()
    .background(ColorPalette.surface)
}
