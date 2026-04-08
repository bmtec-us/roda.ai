// Sources/RodaAi/Features/Voice/VoiceModeView.swift
//
// Voice mode com orbe animado estilo ChatGPT Advanced Voice.
// Full-screen, orb central que reage ao estado, toque para falar.
//
// Liquid Glass: todos os elementos (label de estado, halo do orbe, transcript,
// botao de cancelar) vivem dentro de um `GlassContainer` e recebem
// `glassID` em um namespace compartilhado para que os shapes morfem
// entre os estados idle/listening/processing/speaking.
import SwiftUI
import RodaAiCore

struct VoiceModeView: View {
    @ObservedObject var voiceService: VoiceService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var voiceGlass

    var body: some View {
        ZStack {
            // Full-screen tap target
            Color.clear
                .contentShape(Rectangle())

            GlassContainer(spacing: 40) {
                VStack(spacing: 0) {
                    Spacer()

                    // State label (small, above orb)
                    stateLabel
                        .padding(.bottom, 24)

                    // Central animated orb com halo Liquid Glass
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 260, height: 260)
                            .glassShape(
                                Circle(),
                                tint: orbTint,
                                interactive: true
                            )
                            .glassID(GlassNamespaceID.voiceOrbHalo, in: voiceGlass)

                        VoiceOrb(state: orbState)
                    }
                    .onTapGesture {
                        handleTap()
                    }
                    .accessibilityLabel(isActive ? "voice.action.stop" : "voice.action.start")
                    .accessibilityAddTraits(.isButton)

                    // Transcript & response (below orb)
                    transcriptSection
                        .padding(.top, 32)

                    Spacer()

                    // Bottom controls
                    bottomControls
                        .padding(.bottom, 20)
                }
                .padding(.horizontal)
            }
        }
        .animation(
            reduceMotion ? nil : .spring(duration: 0.5),
            value: voiceService.state
        )
    }

    // MARK: - State Label

    private var stateLabel: some View {
        Group {
            switch voiceService.state {
            case .idle:
                Text("voice.state.idle")
                    .foregroundStyle(.secondary)
            case .listening:
                if voiceService.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("voice.state.listening")
                        .foregroundStyle(.primary)
                } else {
                    Text("Aguardando \(VoiceService.silenceAutoSendSeconds)s de silencio para enviar")
                        .foregroundStyle(.primary)
                }
            case .processing:
                Text("voice.state.processing")
                    .foregroundStyle(.primary)
            case .speaking:
                Text("voice.state.speaking")
                    .foregroundStyle(.primary)
            case .error(let error):
                Text(error.errorDescription ?? String(localized: "voice.state.error"))
                    .foregroundStyle(.red)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassShape(Capsule())
        .glassID(GlassNamespaceID.voiceStateLabel, in: voiceGlass)
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcriptSection: some View {
        VStack(spacing: 12) {
            if !voiceService.transcript.isEmpty {
                Text(voiceService.transcript)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 24)
                    .transition(.blurReplace)
            }
            if !voiceService.response.isEmpty {
                Text(cleanResponseForVoice(voiceService.response))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .padding(.horizontal, 24)
                    .transition(.blurReplace)
            }
        }
        .padding(.vertical, 10)
        .glassShape(RoundedRectangle(cornerRadius: 20))
        .glassID(GlassNamespaceID.voiceTranscript, in: voiceGlass)
        .animation(.spring(duration: 0.4), value: voiceService.transcript)
        .animation(.spring(duration: 0.4), value: voiceService.response)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack {
            Spacer()

            if isActive {
                Button {
                    voiceService.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                }
                .tint(.red)
                .glassButtonStyle(.glass)
                .glassID(GlassNamespaceID.voiceCancelButton, in: voiceGlass)
                .accessibilityLabel("voice.action.stop")
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func handleTap() {
        Task {
            if case .idle = voiceService.state {
                try? await voiceService.startConversation()
            } else {
                voiceService.cancel()
            }
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

    private var orbState: VoiceOrb.VoiceOrbState {
        switch voiceService.state {
        case .idle: return .idle
        case .listening: return .listening
        case .processing: return .processing
        case .speaking: return .speaking
        case .error: return .error
        }
    }

    private var orbTint: Color? {
        switch voiceService.state {
        case .idle: return nil
        case .listening: return .green
        case .processing: return .blue
        case .speaking: return ColorPalette.accent
        case .error: return .red
        }
    }

    private func cleanResponseForVoice(_ text: String) -> String {
        var value = text
        value = value.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "`", with: "")
        value = value.replacingOccurrences(of: "**", with: "")
        value = value.replacingOccurrences(of: "__", with: "")
        value = value.replacingOccurrences(of: "(?m)^\\s*#{1,6}\\s*", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?m)^\\s*[-*+]\\s+", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\[[^\\]]+\\]\\([^\\)]+\\)", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
