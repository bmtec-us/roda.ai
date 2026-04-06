// Tests/RodaAiTests/Onboarding/OnboardingStateTests.swift
import XCTest
@testable import RodaAi

final class OnboardingStateTests: XCTestCase {

    // MARK: - Valid Transitions

    func testWelcomeToSelectModel() {
        var state = OnboardingState.welcome
        try! state.transition(.next)
        XCTAssertEqual(state, .selectModel)
    }

    func testSelectModelToFirstChat() {
        var state = OnboardingState.selectModel
        try! state.transition(.next)
        XCTAssertEqual(state, .firstChat)
    }

    func testFirstChatToReady() {
        var state = OnboardingState.firstChat
        try! state.transition(.next)
        XCTAssertEqual(state, .ready)
    }

    func testReadyToCompleted() {
        var state = OnboardingState.ready
        try! state.transition(.complete)
        XCTAssertEqual(state, .completed)
    }

    // MARK: - Skip Transitions

    func testSkipFromSelectModel() {
        var state = OnboardingState.selectModel
        try! state.transition(.skip)
        XCTAssertEqual(state, .ready)
    }

    func testSkipFromFirstChat() {
        var state = OnboardingState.firstChat
        try! state.transition(.skip)
        XCTAssertEqual(state, .ready)
    }

    // MARK: - Invalid Transitions

    func testCannotSkipFromWelcome() {
        var state = OnboardingState.welcome
        XCTAssertThrowsError(try state.transition(.skip)) { error in
            XCTAssertTrue(error is OnboardingStateError)
        }
    }

    func testCannotGoNextFromReady() {
        var state = OnboardingState.ready
        XCTAssertThrowsError(try state.transition(.next)) { error in
            XCTAssertTrue(error is OnboardingStateError)
        }
    }

    func testCannotTransitionFromCompleted() {
        var state = OnboardingState.completed
        XCTAssertThrowsError(try state.transition(.next)) { error in
            XCTAssertTrue(error is OnboardingStateError)
        }
        XCTAssertThrowsError(try state.transition(.skip)) { error in
            XCTAssertTrue(error is OnboardingStateError)
        }
        XCTAssertThrowsError(try state.transition(.complete)) { error in
            XCTAssertTrue(error is OnboardingStateError)
        }
    }

    // MARK: - Full Sequence

    func testFullOnboardingSequence() {
        var state = OnboardingState.welcome
        try! state.transition(.next)      // → selectModel
        try! state.transition(.next)      // → firstChat
        try! state.transition(.next)      // → ready
        try! state.transition(.complete)  // → completed
        XCTAssertEqual(state, .completed)
    }

    func testSkipSequence() {
        var state = OnboardingState.welcome
        try! state.transition(.next)     // → selectModel
        try! state.transition(.skip)     // → ready
        try! state.transition(.complete) // → completed
        XCTAssertEqual(state, .completed)
    }
}
