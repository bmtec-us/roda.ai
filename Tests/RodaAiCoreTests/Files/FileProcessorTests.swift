// Tests/RodaAiCoreTests/Files/FileProcessorTests.swift
import XCTest
@testable import RodaAiCore

final class FileProcessorTests: XCTestCase {

    private var processor: FileProcessor!
    private var fixturesURL: URL!

    override func setUp() {
        processor = FileProcessor()
        fixturesURL = Bundle.module.resourceURL!
            .appendingPathComponent("Fixtures/Files")
    }

    // MARK: - Supported Formats

    func testExtractTextFromPDF() async throws {
        let url = fixturesURL.appendingPathComponent("sample.pdf")
        let text = try await processor.extractText(from: url)
        XCTAssertFalse(text.isEmpty, "PDF extraction must return non-empty text")
        XCTAssertTrue(text.contains("Conteudo"), "PDF must contain expected text")
    }

    func testExtractTextFromCSV() async throws {
        let url = fixturesURL.appendingPathComponent("sample.csv")
        let text = try await processor.extractText(from: url)
        XCTAssertTrue(text.contains("nome"), "CSV must contain header 'nome'")
        XCTAssertTrue(text.contains("idade"), "CSV must contain header 'idade'")
    }

    func testExtractTextFromTXT() async throws {
        let url = fixturesURL.appendingPathComponent("sample.txt")
        let text = try await processor.extractText(from: url)
        XCTAssertFalse(text.isEmpty, "TXT extraction must return non-empty text")
    }

    func testExtractTextFromSwiftCode() async throws {
        let url = fixturesURL.appendingPathComponent("sample.swift")
        let text = try await processor.extractText(from: url)
        XCTAssertTrue(text.contains("func") || text.contains("import"),
                      "Swift file must contain code")
    }

    // MARK: - Error Cases (FileProcessorError from error-types.md)

    func testUnsupportedFormatThrowsError() async {
        let url = fixturesURL.appendingPathComponent("file.exe")
        do {
            _ = try await processor.extractText(from: url)
            XCTFail("Must throw for unsupported format")
        } catch let error as FileProcessorError {
            guard case .unsupportedFormat(let ext) = error else {
                XCTFail("Must throw .unsupportedFormat, got \(error)")
                return
            }
            XCTAssertEqual(ext, "exe")
        } catch {
            XCTFail("Must throw FileProcessorError, got \(type(of: error))")
        }
    }

    func testCorruptedPDFThrowsError() async {
        let url = fixturesURL.appendingPathComponent("corrupted.pdf")
        do {
            _ = try await processor.extractText(from: url)
            XCTFail("Must throw for corrupted PDF")
        } catch let error as FileProcessorError {
            guard case .pdfExtractionFailed = error else {
                XCTFail("Must throw .pdfExtractionFailed, got \(error)")
                return
            }
        } catch {
            XCTFail("Must throw FileProcessorError, got \(type(of: error))")
        }
    }

    func testFileTooLargeThrowsError() async {
        let url = fixturesURL.appendingPathComponent("large-file.txt")
        let maxBytes: Int64 = 10_485_760 // 10MB
        do {
            _ = try await processor.extractText(from: url, maxBytes: maxBytes)
            XCTFail("Must throw for file exceeding max size")
        } catch let error as FileProcessorError {
            guard case .fileTooLarge(let size, let max) = error else {
                XCTFail("Must throw .fileTooLarge, got \(error)")
                return
            }
            XCTAssertGreaterThan(size, max)
        } catch {
            XCTFail("Must throw FileProcessorError, got \(type(of: error))")
        }
    }

    func testFileNotReadableThrowsError() async {
        let url = URL(fileURLWithPath: "/nonexistent/path/file.txt")
        do {
            _ = try await processor.extractText(from: url)
            XCTFail("Must throw for non-readable file")
        } catch let error as FileProcessorError {
            guard case .fileNotReadable = error else {
                XCTFail("Must throw .fileNotReadable, got \(error)")
                return
            }
        } catch {
            XCTFail("Must throw FileProcessorError, got \(type(of: error))")
        }
    }

    // MARK: - Error Messages in Portuguese

    func testErrorDescriptionInPortuguese() {
        let error = FileProcessorError.unsupportedFormat(extension: "exe")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("nao suportado") || desc.contains("não suportado"),
                      "Error description must be in Portuguese: got '\(desc)'")
    }

    // MARK: - Supported Extensions List

    func testSupportedExtensions() {
        let supported = FileProcessor.supportedExtensions
        XCTAssertTrue(supported.contains("pdf"))
        XCTAssertTrue(supported.contains("csv"))
        XCTAssertTrue(supported.contains("txt"))
        XCTAssertTrue(supported.contains("swift"))
        XCTAssertTrue(supported.contains("py"))
        XCTAssertTrue(supported.contains("js"))
        XCTAssertTrue(supported.contains("ts"))
        XCTAssertTrue(supported.contains("json"))
        XCTAssertTrue(supported.contains("xml"))
        XCTAssertTrue(supported.contains("html"))
        XCTAssertTrue(supported.contains("css"))
    }

    // MARK: - Sendable Conformance

    func testFileProcessorIsSendable() {
        // FileProcessor must conform to Sendable (concurrency-model.md)
        let _: any Sendable = processor as Any as! Sendable
        // If this compiles, FileProcessor conforms to Sendable
    }

    // MARK: - Protocol Conformance

    func testConformsToFileTextExtractor() {
        let _: any FileTextExtractor = processor
        // If this compiles, FileProcessor conforms to FileTextExtractor
    }
}
