// Sources/RodaAi/Features/Onboarding/OnboardingView.swift
import SwiftUI
import SwiftData
import RodaAiCore

struct OnboardingView: View {
    @State private var state: OnboardingState = .welcome
    @Environment(\.modelContext) private var modelContext
    @Query private var allPreferences: [UserPreferences]

    var body: some View {
        Group {
            switch state {
            case .welcome:
                OnboardingWelcomeStep(onNext: { try? state.transition(.next) })
            case .selectModel:
                OnboardingModelStep(
                    onNext: { try? state.transition(.next) },
                    onSkip: { try? state.transition(.skip) }
                )
            case .firstChat:
                OnboardingChatStep(
                    onNext: { try? state.transition(.next) },
                    onSkip: { try? state.transition(.skip) }
                )
            case .ready:
                OnboardingReadyStep(onComplete: {
                    markOnboardingComplete()
                    try? state.transition(.complete)
                })
            case .completed:
                EmptyView()
            }
        }
    }

    /// Atualiza a UserPreferences existente (ou cria se nenhuma existir)
    /// e marca onboarding como completo. Antes: criava uma nova row a cada
    /// complete(), acumulando duplicatas com valores inconsistentes.
    private func markOnboardingComplete() {
        // Remove duplicatas existentes (pode haver de runs anteriores com bug)
        if allPreferences.count > 1 {
            for extra in allPreferences.dropFirst() {
                modelContext.delete(extra)
            }
        }

        // Atualiza a primeira existente OU cria nova
        if let existing = allPreferences.first {
            existing.hasCompletedOnboarding = true
        } else {
            let prefs = UserPreferences()
            prefs.hasCompletedOnboarding = true
            modelContext.insert(prefs)
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save onboarding completion: \(error)")
        }
    }
}

// MARK: - Step Views

private struct OnboardingWelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "cpu")
                .font(.system(size: 80))
                .foregroundStyle(ColorPalette.accent)
            Text("onboarding.welcome.title")
                .font(.rodaTitle)
            Text("onboarding.welcome.subtitle")
                .font(.rodaBody)
                .foregroundStyle(ColorPalette.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: onNext) {
                Text("onboarding.continue")
                    .frame(maxWidth: .infinity)
            }
            .tint(ColorPalette.accent)
            .glassButtonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

private struct OnboardingModelStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("onboarding.model.title")
                .font(.rodaTitle)
            Text("onboarding.model.subtitle")
                .font(.rodaBody)
                .foregroundStyle(ColorPalette.textSecondary)
            Spacer()
            Button(action: onNext) {
                Text("onboarding.continue")
                    .frame(maxWidth: .infinity)
            }
            .tint(ColorPalette.accent)
            .glassButtonStyle(.glassProminent)
            .controlSize(.large)
            Button("onboarding.skip", action: onSkip)
                .foregroundStyle(ColorPalette.textSecondary)
        }
        .padding()
    }
}

private struct OnboardingChatStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("onboarding.chat.title")
                .font(.rodaTitle)
            Text("onboarding.chat.subtitle")
                .font(.rodaBody)
                .foregroundStyle(ColorPalette.textSecondary)
            Spacer()
            Button(action: onNext) {
                Text("onboarding.continue")
                    .frame(maxWidth: .infinity)
            }
            .tint(ColorPalette.accent)
            .glassButtonStyle(.glassProminent)
            .controlSize(.large)
            Button("onboarding.skip", action: onSkip)
                .foregroundStyle(ColorPalette.textSecondary)
        }
        .padding()
    }
}

private struct OnboardingReadyStep: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(ColorPalette.success)
            Text("onboarding.ready.title")
                .font(.rodaTitle)
            Spacer()
            Button(action: onComplete) {
                Text("onboarding.ready.button")
                    .frame(maxWidth: .infinity)
            }
            .tint(ColorPalette.accent)
            .glassButtonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding()
    }
}
