// Tests/RodaAiCoreTests/Errors/ErrorLocalizationTests.swift
import XCTest
@testable import RodaAiCore

final class ErrorLocalizationTests: XCTestCase {

    // MARK: - InferenceError Localization

    func testInsufficientMemoryDescriptionInPortuguese() {
        let error = InferenceError.insufficientMemory(required: 8_589_934_592, available: 4_294_967_296)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("insuficiente") || desc.contains("Memoria"),
                      "Must be in Portuguese: '\(desc)'")
        XCTAssertTrue(desc.contains("GB"), "Must include GB units: '\(desc)'")
    }

    func testModelNotFoundDescriptionInPortuguese() {
        let error = InferenceError.modelNotFound(identifier: "gemma-4-e4b")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("nao encontrado") || desc.contains("não encontrado"),
                      "Must be in Portuguese: '\(desc)'")
        XCTAssertTrue(desc.contains("gemma-4-e4b"), "Must include model name: '\(desc)'")
    }

    func testGenerationCancelledDescriptionInPortuguese() {
        let error = InferenceError.generationCancelled
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("cancelada") || desc.contains("cancelado"),
                      "Must be in Portuguese: '\(desc)'")
    }

    func testModelNotLoadedDescriptionInPortuguese() {
        let error = InferenceError.modelNotLoaded
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("modelo") || desc.contains("Nenhum"),
                      "Must be in Portuguese: '\(desc)'")
    }

    // MARK: - DownloadError Localization

    func testNetworkUnavailableDescriptionInPortuguese() {
        let error = DownloadError.networkUnavailable
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("conexao") || desc.contains("internet") || desc.contains("rede"),
                      "Must be in Portuguese: '\(desc)'")
    }

    func testInsufficientStorageDescriptionInPortuguese() {
        let error = DownloadError.insufficientStorage(required: 2_000_000_000, available: 500_000_000)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("insuficiente") || desc.contains("Espaco"),
                      "Must be in Portuguese: '\(desc)'")
    }

    func testRateLimitedDescriptionInPortuguese() {
        let error = DownloadError.rateLimited(retryAfterSeconds: 60)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("requisicoes") || desc.contains("Tente"),
                      "Must be in Portuguese: '\(desc)'")
        XCTAssertTrue(desc.contains("60"), "Must include retry seconds: '\(desc)'")
    }

    // MARK: - FileProcessorError Localization

    func testUnsupportedFormatDescriptionInPortuguese() {
        let error = FileProcessorError.unsupportedFormat(extension: "docx")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("nao suportado") || desc.contains("não suportado"),
                      "Must be in Portuguese: '\(desc)'")
        XCTAssertTrue(desc.contains("docx"), "Must include extension: '\(desc)'")
    }

    func testFileTooLargeDescriptionInPortuguese() {
        let error = FileProcessorError.fileTooLarge(sizeBytes: 20_971_520, maxBytes: 10_485_760)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("grande") || desc.contains("Maximo"),
                      "Must be in Portuguese: '\(desc)'")
    }

    // MARK: - VoiceError Localization

    func testMicPermissionDeniedDescriptionInPortuguese() {
        let error = VoiceError.microphonePermissionDenied
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("microfone") || desc.contains("Microfone"),
                      "Must be in Portuguese: '\(desc)'")
        XCTAssertTrue(desc.contains("Ajustes") || desc.contains("Privacidade"),
                      "Must include settings instructions: '\(desc)'")
    }

    func testNoSpeechDetectedDescriptionInPortuguese() {
        let error = VoiceError.noSpeechDetected
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("fala") || desc.contains("detectada"),
                      "Must be in Portuguese: '\(desc)'")
    }

    // MARK: - PersistenceError Localization

    func testSaveFailedDescriptionInPortuguese() {
        let error = PersistenceError.saveFailed(reason: "Disk full")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("salvar") || desc.contains("Erro"),
                      "Must be in Portuguese: '\(desc)'")
    }

    // MARK: - All Errors Have Descriptions

    func testAllInferenceErrorsHaveDescriptions() {
        let errors: [InferenceError] = [
            .modelNotFound(identifier: "test"),
            .modelCorrupted(identifier: "test", reason: "bad"),
            .insufficientMemory(required: 8, available: 4),
            .unsupportedArchitecture(identifier: "test"),
            .generationFailed(reason: "fail"),
            .generationCancelled,
            .contextLengthExceeded(maxTokens: 2048),
            .tokenizerNotFound(identifier: "test"),
            .tokenizationFailed(reason: "fail"),
            .modelNotLoaded,
            .metalNotAvailable,
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) must have errorDescription")
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) errorDescription must not be empty")
        }
    }
}
