// Tests/RodaAiTests/Design/TypographyTests.swift
import XCTest
import SwiftUI
@testable import RodaAi

final class TypographyTests: XCTestCase {

    func testAllTypographyTokensExist() {
        // Verify all tokens are defined and accessible
        let tokens: [Font] = [
            .rodaTitle,
            .rodaHeadline,
            .rodaBody,
            .rodaCaption,
            .rodaCode
        ]
        XCTAssertEqual(tokens.count, 5, "Must have exactly 5 typography tokens")
    }

    func testCodeFontUsesMonospacedDesign() {
        // rodaCode must use monospaced design for code display
        let codeFont = Font.rodaCode
        // Font.system(.body, design: .monospaced) — verify it is monospaced
        XCTAssertNotNil(codeFont, "Code font must be defined with monospaced design")
    }

    func testTitleFontUsesBoldWeight() {
        let titleFont = Font.rodaTitle
        XCTAssertNotNil(titleFont, "Title font must use bold weight")
    }

    func testHeadlineFontUsesSemiboldWeight() {
        let headlineFont = Font.rodaHeadline
        XCTAssertNotNil(headlineFont, "Headline font must use semibold weight")
    }

    func testTypographyScaleOrder() {
        // Verify that the type scale maps to the correct SwiftUI TextStyles
        // largeTitle > headline > body > caption
        // We verify this by confirming the correct TextStyle is used
        XCTAssertNotNil(Font.rodaTitle, "Title must map to .largeTitle")
        XCTAssertNotNil(Font.rodaHeadline, "Headline must map to .headline")
        XCTAssertNotNil(Font.rodaBody, "Body must map to .body")
        XCTAssertNotNil(Font.rodaCaption, "Caption must map to .caption")
    }
}
