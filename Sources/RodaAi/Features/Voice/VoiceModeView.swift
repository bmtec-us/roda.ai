// Sources/RodaAi/Features/Voice/VoiceModeView.swift
import SwiftUI
import RodaAiCore

struct VoiceModeView: View {
    @ObservedObject var voiceService: VoiceService

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // State indicator
            stateIndicator

            // Waveform / Animation
            VoiceWaveform(isActive: isActive)
                .frame(height: 60)
                .padding(.horizontal)

            // Transcript / Response
            transcriptSection

            Spacer()

            // Microphone button
            microphoneButton
                .padding(.bottom, 40)
        }
        .background(ColorPalette.surface)
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        switch voiceService.state {
        case .idle:
            Text("Toque para falar")
                .font(.rodaHeadline)
                .foregroundStyle(ColorPalette.textSecondary)
        case .listening:
            Text("Ouvindo...")
                .font(.rodaHeadline)
                .foregroundStyle(ColorPalette.accent)
        case .processing:
            Text("Processando...")
                .font(.rodaHeadline)
                .foregroundStyle(ColorPalette.accent)
        case .speaking:
            Text("Respondendo...")
                .font(.rodaHeadline)
                .foregroundStyle(ColorPalette.accent)
        case .error(let error):
            Text(error.errorDescription ?? "Erro")
                .font(.rodaBody)
                .foregroundStyle(ColorPalette.error)
        }
    }

    // MARK: - Transcript Section

    @ViewBuilder
    private var transcriptSection: some View {
        VStack(spacing: 12) {
            if !voiceService.transcript.isEmpty {
                Text(voiceService.transcript)
                    .font(.rodaBody)
                    .foregroundStyle(ColorPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            if !voiceService.response.isEmpty {
                Text(voiceService.response)
                    .font(.rodaBody)
                    .foregroundStyle(ColorPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Microphone Button

    private var microphoneButton: some View {
        Button {
            Task {
                if case .idle = voiceService.state {
                    try? await voiceService.startConversation()
                } else {
                    voiceService.cancel()
                }
            }
        } label: {
            Image(systemName: isActive ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(isActive ? ColorPalette.error : ColorPalette.accent)
        }
    }

    private var isActive: Bool {
        switch voiceService.state {
        case .idle, .error:
            return false
        default:
            return true
        }
    }
}
