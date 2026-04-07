// Sources/RodaAiCore/Chat/ChatState.swift
import Foundation

public enum ChatStateError: Error, Equatable {
    case invalidTransition(from: String, event: String)
}

public enum ChatEvent: Equatable, Sendable {
    case send(modelIdentifier: String)
    case firstToken
    case tokenReceived
    case finished(durationMs: Int)
    case cancel
    case error(InferenceError)
    case reset
}

public enum ChatState: Equatable, Sendable {
    case idle
    case loading(modelIdentifier: String)
    case streaming(tokensReceived: Int)
    case completed(totalTokens: Int, durationMs: Int)
    case error(InferenceError)

    public mutating func transition(_ event: ChatEvent) throws {
        switch (self, event) {
        case (.idle, .send(let model)):
            self = .loading(modelIdentifier: model)
        case (.loading, .firstToken):
            self = .streaming(tokensReceived: 0)
        case (.streaming(let count), .tokenReceived):
            self = .streaming(tokensReceived: count + 1)
        case (.streaming(let count), .finished(let duration)):
            self = .completed(totalTokens: count, durationMs: duration)
        case (.loading, .finished(let duration)):
            self = .completed(totalTokens: 0, durationMs: duration)
        case (.streaming, .cancel), (.loading, .cancel):
            self = .idle
        case (.loading, .error(let e)), (.streaming, .error(let e)):
            self = .error(e)
        case (.error, .reset), (.completed, .reset):
            self = .idle
        default:
            throw ChatStateError.invalidTransition(
                from: "\(self)", event: "\(event)"
            )
        }
    }
}

extension ChatState {
    public var isStreaming: Bool {
        switch self {
        case .loading, .streaming: return true
        default: return false
        }
    }

    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    public var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
