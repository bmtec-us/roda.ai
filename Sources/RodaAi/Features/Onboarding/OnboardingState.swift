// Sources/RodaAi/Features/Onboarding/OnboardingState.swift
import Foundation

enum OnboardingState: Equatable, Sendable {
    case welcome
    case selectModel
    case firstChat
    case ready
    case completed

    mutating func transition(_ event: OnboardingEvent) throws {
        switch (self, event) {
        case (.welcome, .next):
            self = .selectModel
        case (.selectModel, .next):
            self = .firstChat
        case (.selectModel, .skip):
            self = .ready
        case (.firstChat, .next):
            self = .ready
        case (.firstChat, .skip):
            self = .ready
        case (.ready, .complete):
            self = .completed
        default:
            throw OnboardingStateError.invalidTransition(from: self, event: event)
        }
    }
}

enum OnboardingEvent: Sendable {
    case next
    case skip
    case complete
}

struct OnboardingStateError: Error {
    let from: OnboardingState
    let event: OnboardingEvent

    static func invalidTransition(from: OnboardingState, event: OnboardingEvent) -> OnboardingStateError {
        OnboardingStateError(from: from, event: event)
    }
}
