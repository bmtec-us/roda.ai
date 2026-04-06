// Sources/RodaAiCore/Voice/VoiceState.swift
import Foundation

public enum VoiceState: Equatable, Sendable {
    case idle
    case listening(partialTranscript: String)
    case processing(fullTranscript: String)
    case speaking(responseText: String)
    case error(VoiceError)

    public mutating func transition(_ event: VoiceEvent) throws {
        switch (self, event) {
        // From idle
        case (.idle, .startVoice):
            self = .listening(partialTranscript: "")

        // From listening
        case (.listening, .partialTranscript(let text)):
            self = .listening(partialTranscript: text)
        case (.listening, .speechDone(let transcript)):
            self = .processing(fullTranscript: transcript)
        case (.listening, .noSpeech):
            self = .error(.noSpeechDetected)
        case (.listening, .cancel):
            self = .idle

        // From processing
        case (.processing, .responseReady(let text)):
            self = .speaking(responseText: text)
        case (.processing, .error(let voiceError)):
            self = .error(voiceError)
        case (.processing, .cancel):
            self = .idle

        // From speaking
        case (.speaking, .speechDone):
            self = .idle
        case (.speaking, .interrupted):
            self = .idle
        case (.speaking, .cancel):
            self = .idle

        // From error
        case (.error, .reset):
            self = .idle

        default:
            throw VoiceStateError.invalidTransition(from: self, event: event)
        }
    }
}

public enum VoiceEvent: Sendable {
    case startVoice
    case partialTranscript(String)
    case speechDone(transcript: String)
    case noSpeech
    case responseReady(text: String)
    case interrupted
    case cancel
    case error(VoiceError)
    case reset
}

public struct VoiceStateError: Error {
    public let from: VoiceState
    public let event: VoiceEvent

    public static func invalidTransition(from: VoiceState, event: VoiceEvent) -> VoiceStateError {
        VoiceStateError(from: from, event: event)
    }
}
