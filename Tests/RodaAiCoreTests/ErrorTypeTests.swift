import XCTest
@testable import RodaAiCore

final class ErrorTypeTests: XCTestCase {

    // MARK: - InferenceError

    func testInferenceErrorIsEquatable() {
        let error1 = InferenceError.modelNotFound(identifier: "test")
        let error2 = InferenceError.modelNotFound(identifier: "test")
        XCTAssertEqual(error1, error2)
    }

    func testInferenceErrorHasLocalizedDescription() {
        let error = InferenceError.insufficientMemory(required: 8_589_934_592, available: 4_294_967_296)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Memoria insuficiente"))
    }

    func testInferenceErrorModelNotLoadedDescription() {
        let error = InferenceError.modelNotLoaded
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Nenhum modelo carregado"))
    }

    // MARK: - DownloadError

    func testDownloadErrorIsEquatable() {
        let error1 = DownloadError.networkUnavailable
        let error2 = DownloadError.networkUnavailable
        XCTAssertEqual(error1, error2)
    }

    func testDownloadErrorHasLocalizedDescription() {
        let error = DownloadError.insufficientStorage(required: 2_097_152, available: 1_048_576)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Espaco insuficiente"))
    }

    // MARK: - FileProcessorError

    func testFileProcessorErrorIsEquatable() {
        let error1 = FileProcessorError.unsupportedFormat(extension: "exe")
        let error2 = FileProcessorError.unsupportedFormat(extension: "exe")
        XCTAssertEqual(error1, error2)
    }

    func testFileProcessorErrorHasLocalizedDescription() {
        let error = FileProcessorError.unsupportedFormat(extension: "exe")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains(".exe"))
    }

    // MARK: - VoiceError

    func testVoiceErrorIsEquatable() {
        let error1 = VoiceError.microphonePermissionDenied
        let error2 = VoiceError.microphonePermissionDenied
        XCTAssertEqual(error1, error2)
    }

    func testVoiceErrorHasLocalizedDescription() {
        let error = VoiceError.microphonePermissionDenied
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("microfone"))
    }

    // MARK: - PersistenceError

    func testPersistenceErrorIsEquatable() {
        let id = UUID()
        let error1 = PersistenceError.conversationNotFound(id: id)
        let error2 = PersistenceError.conversationNotFound(id: id)
        XCTAssertEqual(error1, error2)
    }

    func testPersistenceErrorHasLocalizedDescription() {
        let error = PersistenceError.saveFailed(reason: "disk full")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("salvar"))
    }
}
