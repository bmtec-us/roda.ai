// Sources/RodaAi/Features/Onboarding/OnboardingView.swift
import SwiftUI
import RodaAiCore

struct OnboardingView: View {
    @State private var state: OnboardingState = .welcome
    @Environment(\.modelContext) private var modelContext

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
                    try? state.transition(.complete)
                    markOnboardingComplete()
                })
            case .completed:
                EmptyView()
            }
        }
    }

    private func markOnboardingComplete() {
        let prefs = UserPreferences()
        prefs.hasCompletedOnboarding = true
        modelContext.insert(prefs)
        try? modelContext.save()
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
                Text("Continuar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ColorPalette.accent)
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
                Text("Continuar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ColorPalette.accent)
            Button("Pular", action: onSkip)
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
                Text("Continuar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ColorPalette.accent)
            Button("Pular", action: onSkip)
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
            .buttonStyle(.borderedProminent)
            .tint(ColorPalette.accent)
        }
        .padding()
    }
}
