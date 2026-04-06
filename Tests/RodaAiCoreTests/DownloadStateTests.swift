import XCTest
@testable import RodaAiCore

final class DownloadStateTests: XCTestCase {

    func testInitialStateIsQueued() {
        let state = DownloadState.queued
        XCTAssertEqual(state, .queued)
    }

    func testDownloadingProgress() {
        let state = DownloadState.downloading(progress: 0.5, bytesDownloaded: 500_000_000, totalBytes: 1_000_000_000)
        if case .downloading(let progress, _, _) = state {
            XCTAssertEqual(progress, 0.5, accuracy: 0.001)
        } else {
            XCTFail("Expected downloading state")
        }
    }

    func testInstalledState() {
        let state = DownloadState.installed(sizeOnDisk: 2_000_000_000)
        if case .installed(let size) = state {
            XCTAssertEqual(size, 2_000_000_000)
        } else {
            XCTFail("Expected installed state")
        }
    }

    func testFailedState() {
        let state = DownloadState.failed(.networkUnavailable)
        if case .failed(let error) = state {
            XCTAssertEqual(error, .networkUnavailable)
        } else {
            XCTFail("Expected failed state")
        }
    }

    func testModelLifecycleStateAvailable() {
        let entry = CatalogEntry(
            identifier: "test-model",
            displayName: "Test Model",
            provider: "test",
            familyName: "test",
            parameterCount: "2B",
            quantization: "4-bit",
            downloadSizeBytes: 2_000_000_000,
            estimatedRAMBytes: 2_500_000_000,
            portugueseRating: .bom,
            cpuUsageLevel: .medio,
            minimumRAM: 4,
            isVisionCapable: false,
            isReasoningCapable: false,
            huggingFaceRepoId: "test/test-model"
        )
        let state = ModelLifecycleState.available(catalogEntry: entry)
        if case .available(let e) = state {
            XCTAssertEqual(e.identifier, "test-model")
        } else {
            XCTFail("Expected available state")
        }
    }
}
