// Tests/RodaAiTests/Design/ComponentTests.swift
import XCTest
import SwiftUI
@testable import RodaAi

final class ComponentTests: XCTestCase {

    // MARK: - GlassCard

    func testGlassCardInitializesWithContent() {
        let card = GlassCard { Text("Test content") }
        XCTAssertNotNil(card, "GlassCard must initialize with content closure")
    }

    func testGlassCardHasCornerRadius() {
        XCTAssertGreaterThan(GlassCard.cornerRadius, 0, "GlassCard must have positive corner radius")
    }

    // MARK: - ProgressRing

    func testProgressRingShowsZeroProgress() {
        let ring = ProgressRing(progress: 0.0)
        XCTAssertEqual(ring.progress, 0.0, "ProgressRing must show 0% when progress is 0.0")
    }

    func testProgressRingShowsHalfProgress() {
        let ring = ProgressRing(progress: 0.5)
        XCTAssertEqual(ring.progress, 0.5, "ProgressRing must show 50% when progress is 0.5")
    }

    func testProgressRingShowsFullProgress() {
        let ring = ProgressRing(progress: 1.0)
        XCTAssertEqual(ring.progress, 1.0, "ProgressRing must show 100% when progress is 1.0")
    }

    func testProgressRingClampsOverflow() {
        let ring = ProgressRing(progress: 1.5)
        XCTAssertEqual(ring.clampedProgress, 1.0, "ProgressRing must clamp progress to 1.0 max")
    }

    func testProgressRingClampsUnderflow() {
        let ring = ProgressRing(progress: -0.5)
        XCTAssertEqual(ring.clampedProgress, 0.0, "ProgressRing must clamp progress to 0.0 min")
    }

    // MARK: - AnimatedDots

    func testAnimatedDotsRespectsReducedMotion() {
        let dots = AnimatedDots(reduceMotion: true)
        XCTAssertTrue(dots.isStatic, "AnimatedDots must be static when Reduced Motion is enabled")
    }

    func testAnimatedDotsAnimatesWhenMotionAllowed() {
        let dots = AnimatedDots(reduceMotion: false)
        XCTAssertFalse(dots.isStatic, "AnimatedDots must animate when Reduced Motion is disabled")
    }

    func testAnimatedDotsHasThreeDots() {
        let dots = AnimatedDots(reduceMotion: false)
        XCTAssertEqual(dots.dotCount, 3, "AnimatedDots must display exactly 3 dots")
    }

    // MARK: - CodeBlockView

    func testCodeBlockViewInitializesWithCode() {
        let block = CodeBlockView(code: "print(\"hello\")", language: "swift")
        XCTAssertEqual(block.code, "print(\"hello\")")
        XCTAssertEqual(block.language, "swift")
    }

    func testCodeBlockViewHandlesEmptyLanguage() {
        let block = CodeBlockView(code: "x = 1", language: nil)
        XCTAssertNil(block.language, "CodeBlockView must accept nil language")
    }
}
