import XCTest
@testable import RodaAiCore

final class ValueTypeTests: XCTestCase {

    // MARK: - MessageRole

    func testMessageRoleRawValues() {
        XCTAssertEqual(MessageRole.user.rawValue, "user")
        XCTAssertEqual(MessageRole.assistant.rawValue, "assistant")
        XCTAssertEqual(MessageRole.system.rawValue, "system")
    }

    func testMessageRoleIsCodable() throws {
        let role = MessageRole.assistant
        let data = try JSONEncoder().encode(role)
        let decoded = try JSONDecoder().decode(MessageRole.self, from: data)
        XCTAssertEqual(role, decoded)
    }

    // MARK: - ChatMessage

    func testChatMessageCreation() {
        let msg = ChatMessage(role: .user, content: "Ola")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content, "Ola")
    }

    func testChatMessageIsSendable() {
        // Compilacao garante Sendable; testar uso cross-isolation
        let msg = ChatMessage(role: .user, content: "Teste")
        Task { @MainActor in
            _ = msg.content // Se compilar, e Sendable
        }
        XCTAssertTrue(true) // Compilacao e suficiente
    }

    // MARK: - GenerationConfig

    func testGenerationConfigDefaults() {
        let config = GenerationConfig()
        XCTAssertEqual(config.temperature, 0.7, accuracy: 0.001)
        XCTAssertEqual(config.topP, 0.95, accuracy: 0.001)
        XCTAssertEqual(config.maxTokens, 2048)
        XCTAssertEqual(config.repetitionPenalty, 1.1, accuracy: 0.001)
        XCTAssertNil(config.seed)
    }

    func testGenerationConfigCustomValues() {
        let config = GenerationConfig(temperature: 0.3, topP: 0.8, maxTokens: 512, repetitionPenalty: 1.2, seed: 42)
        XCTAssertEqual(config.temperature, 0.3, accuracy: 0.001)
        XCTAssertEqual(config.topP, 0.8, accuracy: 0.001)
        XCTAssertEqual(config.maxTokens, 512)
        XCTAssertEqual(config.seed, 42)
    }

    // MARK: - PortugueseRating

    func testPortugueseRatingAllCases() {
        let cases = PortugueseRating.allCases
        XCTAssertEqual(cases.count, 4)
        XCTAssertTrue(cases.contains(.excelente))
        XCTAssertTrue(cases.contains(.bom))
        XCTAssertTrue(cases.contains(.razoavel))
        XCTAssertTrue(cases.contains(.limitado))
    }

    // MARK: - CPUUsageLevel

    func testCPUUsageLevelAllCases() {
        let cases = CPUUsageLevel.allCases
        XCTAssertEqual(cases.count, 4)
    }

    // MARK: - Attachment

    func testAttachmentCreation() {
        let url = URL(fileURLWithPath: "/tmp/test.pdf")
        let attachment = Attachment(url: url, mimeType: "application/pdf", extractedText: "conteudo")
        XCTAssertEqual(attachment.url, url)
        XCTAssertEqual(attachment.mimeType, "application/pdf")
        XCTAssertEqual(attachment.extractedText, "conteudo")
    }
}
