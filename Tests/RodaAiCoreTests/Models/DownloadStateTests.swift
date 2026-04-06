// Tests/RodaAiCoreTests/Models/DownloadStateTests.swift
import Testing
@testable import RodaAiCore

@Suite("DownloadState Transitions")
struct DownloadStateTests {

    // MARK: - Transicoes Validas

    @Test("queued -> downloading via start()")
    func testQueuedToDownloading() throws {
        var state = DownloadState.queued
        try state.transition(.start)
        #expect(state == .downloading(progress: 0, bytesDownloaded: 0, totalBytes: 0))
    }

    @Test("downloading -> paused via pause()")
    func testDownloadingToPaused() throws {
        var state = DownloadState.downloading(
            progress: 0.5, bytesDownloaded: 1_000_000_000, totalBytes: 2_000_000_000
        )
        try state.transition(.pause)
        #expect(state == .paused(
            bytesDownloaded: 1_000_000_000, totalBytes: 2_000_000_000
        ))
    }

    @Test("paused -> downloading via resume()")
    func testPausedToDownloading() throws {
        var state = DownloadState.paused(
            bytesDownloaded: 1_000_000_000, totalBytes: 2_000_000_000
        )
        try state.transition(.resume)
        #expect(state == .downloading(
            progress: 0.5, bytesDownloaded: 1_000_000_000, totalBytes: 2_000_000_000
        ))
    }

    @Test("downloading -> validating via complete()")
    func testDownloadingToValidating() throws {
        var state = DownloadState.downloading(
            progress: 1.0, bytesDownloaded: 2_000_000_000, totalBytes: 2_000_000_000
        )
        try state.transition(.complete)
        #expect(state == .validating)
    }

    @Test("validating -> installed via valid()")
    func testValidatingToInstalled() throws {
        var state = DownloadState.validating
        try state.transition(.valid(sizeOnDisk: 2_000_000_000))
        #expect(state == .installed(sizeOnDisk: 2_000_000_000))
    }

    @Test("validating -> failed via invalid()")
    func testValidatingToFailed() throws {
        var state = DownloadState.validating
        let error = DownloadError.checksumMismatch(
            file: "model.safetensors", expected: "abc123", actual: "def456"
        )
        try state.transition(.invalid(error))
        #expect(state == .failed(error))
    }

    @Test("downloading -> failed via error()")
    func testDownloadingToFailed() throws {
        var state = DownloadState.downloading(
            progress: 0.3, bytesDownloaded: 600_000_000, totalBytes: 2_000_000_000
        )
        try state.transition(.error(.networkUnavailable))
        #expect(state == .failed(.networkUnavailable))
    }

    @Test("failed -> downloading via retry()")
    func testFailedToDownloading() throws {
        var state = DownloadState.failed(.networkUnavailable)
        try state.transition(.retry)
        #expect(state == .downloading(progress: 0, bytesDownloaded: 0, totalBytes: 0))
    }

    @Test("downloading updates progress via progressUpdate()")
    func testProgressUpdate() throws {
        var state = DownloadState.downloading(
            progress: 0.0, bytesDownloaded: 0, totalBytes: 2_000_000_000
        )
        try state.transition(.progressUpdate(
            bytesDownloaded: 500_000_000, totalBytes: 2_000_000_000
        ))
        #expect(state == .downloading(
            progress: 0.25, bytesDownloaded: 500_000_000, totalBytes: 2_000_000_000
        ))
    }

    // MARK: - Transicoes Invalidas

    @Test("queued does not accept pause")
    func testQueuedRejectsPause() {
        var state = DownloadState.queued
        #expect(throws: DownloadStateError.self) {
            try state.transition(.pause)
        }
    }

    @Test("installed does not accept start")
    func testInstalledRejectsStart() {
        var state = DownloadState.installed(sizeOnDisk: 2_000_000_000)
        #expect(throws: DownloadStateError.self) {
            try state.transition(.start)
        }
    }

    // MARK: - Sequencia Completa

    @Test("full lifecycle: queued -> downloading -> validating -> installed")
    func testFullLifecycle() throws {
        var state = DownloadState.queued
        try state.transition(.start)
        try state.transition(.progressUpdate(
            bytesDownloaded: 1_000_000_000, totalBytes: 2_000_000_000
        ))
        try state.transition(.progressUpdate(
            bytesDownloaded: 2_000_000_000, totalBytes: 2_000_000_000
        ))
        try state.transition(.complete)
        try state.transition(.valid(sizeOnDisk: 2_000_000_000))
        #expect(state == .installed(sizeOnDisk: 2_000_000_000))
    }

    // MARK: - Phase 2 Original Test Names (Aliases)
    //
    // Preserve original Phase 2 naming convention. Same coverage as renamed tests
    // above. Both phase docs reference these tests.

    @Test("Phase 2 alias: queued to downloading via start event")
    func testQueuedToDownloadingOnStart() throws {
        var state: DownloadState = .queued
        try state.transition(.start)
        #expect(state == .downloading(progress: 0.0, bytesDownloaded: 0, totalBytes: 0))
    }

    @Test("Phase 2 alias: downloading to paused via pause event")
    func testDownloadingToPausedOnPause() throws {
        var state: DownloadState = .downloading(
            progress: 0.5, bytesDownloaded: 1_000_000_000, totalBytes: 2_000_000_000
        )
        try state.transition(.pause)
        #expect(state == .paused(bytesDownloaded: 1_000_000_000, totalBytes: 2_000_000_000))
    }

    @Test("Phase 2 alias: paused to downloading via resume event")
    func testPausedToDownloadingOnResume() throws {
        var state: DownloadState = .paused(
            bytesDownloaded: 500_000_000, totalBytes: 2_000_000_000
        )
        try state.transition(.resume)
        if case .downloading = state {
            // OK
        } else {
            Issue.record("Expected .downloading after resume")
        }
    }

    @Test("Phase 2 alias: downloading to validating via complete event")
    func testDownloadingToValidatingOnComplete() throws {
        var state: DownloadState = .downloading(
            progress: 1.0, bytesDownloaded: 2_000_000_000, totalBytes: 2_000_000_000
        )
        try state.transition(.complete)
        #expect(state == .validating)
    }

    @Test("Phase 2 alias: validating to installed via valid event")
    func testValidatingToInstalledOnValid() throws {
        var state: DownloadState = .validating
        try state.transition(.valid(sizeOnDisk: 2_000_000_000))
        #expect(state == .installed(sizeOnDisk: 2_000_000_000))
    }

    @Test("Phase 2 alias: validating to failed via invalid event")
    func testValidatingToFailedOnInvalid() throws {
        var state: DownloadState = .validating
        try state.transition(.invalid(.checksumMismatch(file: "model.safetensors", expected: "abc", actual: "def")))
        if case .failed = state {
            // OK
        } else {
            Issue.record("Expected .failed after invalid")
        }
    }

    @Test("Phase 2 alias: downloading to failed via error event")
    func testDownloadingToFailedOnError() throws {
        var state: DownloadState = .downloading(
            progress: 0.3, bytesDownloaded: 600_000_000, totalBytes: 2_000_000_000
        )
        try state.transition(.error(.networkUnavailable))
        if case .failed = state {
            // OK
        } else {
            Issue.record("Expected .failed after error")
        }
    }

    @Test("Phase 2 alias: failed to downloading via retry event")
    func testFailedToDownloadingOnRetry() throws {
        var state: DownloadState = .failed(.networkUnavailable)
        try state.transition(.retry)
        if case .downloading = state {
            // OK
        } else {
            Issue.record("Expected .downloading after retry")
        }
    }
}
