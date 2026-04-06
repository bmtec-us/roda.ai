// Tests/RodaAiTests/Accessibility/AccessibilityLabelTests.swift
import XCTest
@testable import RodaAi

final class AccessibilityLabelTests: XCTestCase {

    // MARK: - Send Button

    func testSendButtonHasAccessibilityLabel() {
        let label = AccessibilityLabels.sendButton
        XCTAssertEqual(label, "Enviar mensagem")
    }

    func testSendButtonHasAccessibilityHint() {
        let hint = AccessibilityHints.sendButton
        XCTAssertEqual(hint, "Toque duas vezes para enviar sua mensagem")
    }

    // MARK: - Model Card

    func testModelCardHasAccessibilityLabel() {
        let label = AccessibilityLabels.modelCard(name: "Gemma 4 E4B", status: "Baixado")
        XCTAssertEqual(label, "Modelo Gemma 4 E4B, Baixado")
    }

    func testModelCardRatingIncludesTextAndIcon() {
        let label = AccessibilityLabels.modelRating(rating: "Bom em Portugues")
        XCTAssertTrue(label.contains("Bom em Portugues"),
                      "Rating must include text description, not just color")
    }

    // MARK: - Voice Button

    func testVoiceButtonLabelReflectsState() {
        let idleLabel = AccessibilityLabels.voiceButton(state: .idle)
        XCTAssertEqual(idleLabel, "Iniciar modo voz")

        let listeningLabel = AccessibilityLabels.voiceButton(state: .listening)
        XCTAssertEqual(listeningLabel, "Parar de ouvir")

        let processingLabel = AccessibilityLabels.voiceButton(state: .processing)
        XCTAssertEqual(processingLabel, "Processando sua pergunta")

        let speakingLabel = AccessibilityLabels.voiceButton(state: .speaking)
        XCTAssertEqual(speakingLabel, "Parar resposta")
    }

    // MARK: - Progress Indicators

    func testProgressRingAccessibilityValue() {
        let value = AccessibilityLabels.downloadProgress(percent: 45)
        XCTAssertEqual(value, "45 por cento baixado")
    }

    // MARK: - Navigation Tabs

    func testTabLabelsInPortuguese() {
        XCTAssertEqual(AccessibilityLabels.tabConversations, "Conversas")
        XCTAssertEqual(AccessibilityLabels.tabModels, "Modelos")
        XCTAssertEqual(AccessibilityLabels.tabVoice, "Voz")
        XCTAssertEqual(AccessibilityLabels.tabSettings, "Ajustes")
    }

    // MARK: - Differentiate Without Color

    func testStatusIndicatorHasNonColorCue() {
        // Status must include icon name AND text, not just color
        let status = AccessibilityLabels.modelStatus(downloaded: true)
        XCTAssertTrue(status.contains("Baixado"),
                      "Status must include text cue for Differentiate Without Color")
    }
}
