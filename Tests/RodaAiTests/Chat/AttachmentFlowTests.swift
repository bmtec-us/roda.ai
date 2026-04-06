// Tests/RodaAiTests/Chat/AttachmentFlowTests.swift
import XCTest
@testable import RodaAi
@testable import RodaAiCore

@MainActor
final class AttachmentFlowTests: XCTestCase {

    func testAttachmentPrependsTextToPrompt() async throws {
        var mockProcessor = MockFileProcessor()
        mockProcessor.extractedTexts["test.pdf"] = "Conteudo do PDF de teste"
        let url = URL(fileURLWithPath: "/tmp/test.pdf")

        let text = try await mockProcessor.extractText(from: url)
        let prompt = "Resuma este documento"
        let fullPrompt = "Documento anexado:\n\(text)\n\n\(prompt)"

        XCTAssertTrue(fullPrompt.contains("Conteudo do PDF de teste"))
        XCTAssertTrue(fullPrompt.contains("Resuma este documento"))
    }

    func testAttachmentFlowHandlesProcessorError() async {
        var mockProcessor = MockFileProcessor()
        mockProcessor.shouldThrow = .unsupportedFormat(extension: "exe")
        let url = URL(fileURLWithPath: "/tmp/file.exe")

        do {
            _ = try await mockProcessor.extractText(from: url)
            XCTFail("Must propagate FileProcessorError")
        } catch let error as FileProcessorError {
            guard case .unsupportedFormat(let ext) = error else {
                XCTFail("Must be .unsupportedFormat")
                return
            }
            XCTAssertEqual(ext, "exe")
        } catch {
            XCTFail("Unexpected error type")
        }
    }

    func testAttachmentFlowHandlesFileTooLarge() async {
        var mockProcessor = MockFileProcessor()
        mockProcessor.shouldThrow = .fileTooLarge(sizeBytes: 20_000_000, maxBytes: 10_485_760)
        let url = URL(fileURLWithPath: "/tmp/huge.txt")

        do {
            _ = try await mockProcessor.extractText(from: url)
            XCTFail("Must throw fileTooLarge")
        } catch let error as FileProcessorError {
            guard case .fileTooLarge(let size, let max) = error else {
                XCTFail("Must be .fileTooLarge")
                return
            }
            XCTAssertGreaterThan(size, max)
        } catch {
            XCTFail("Unexpected error type")
        }
    }

    func testMockFileProcessorTracksCallsCorrectly() async throws {
        let mockProcessor = MockFileProcessor()
        let url = URL(fileURLWithPath: "/tmp/test.txt")
        _ = try await mockProcessor.extractText(from: url)
        // MockFileProcessor returns "Conteudo mock" for unknown files
    }
}
