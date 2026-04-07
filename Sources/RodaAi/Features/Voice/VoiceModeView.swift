// Sources/RodaAi/Features/Voice/VoiceModeView.swift
//
// Voice mode com orbe animado estilo ChatGPT Advanced Voice.
// Full-screen, orb central que reage ao estado, toque para falar.
import SwiftUI
import RodaAiCore

struct VoiceModeView: View {
    @ObservedObject var voiceService: VoiceService

    var body: some View {
        ZStack {
            // Full-screen tap target
            Color.clear
                .contentShape(Rectangle())

            VStack(spacing: 0) {
                Spacer()

                // State label (small, above orb)
                stateLabel
                    .padding(.bottom, 24)

                // Central animated orb — tap to start/stop
                VoiceOrb(state: orbState)
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

    // MARK: - State Label

    private var stateLabel: some View {
        Group {
            switch voiceService.state {
            case .idle:
                Text("voice.state.idle")
                    .foregroundStyle(.secondary)
            case .listening:
                Text("voice.state.listening")
                    .foregroundStyle(.primary)
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
        .animation(.easeInOut(duration: 0.3), value: voiceService.state == .idle)
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
                Text(voiceService.response)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .padding(.horizontal, 24)
                    .transition(.blurReplace)
            }
        }
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
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                }
                .modifier(GlassCircleModifier())
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
}

// MARK: - Glass Circle Button

private struct GlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content
                .glassEffect(in: .circle)
        } else {
            content
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
}
