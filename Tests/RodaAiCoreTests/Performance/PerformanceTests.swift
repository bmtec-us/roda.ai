// Tests/RodaAiCoreTests/Performance/PerformanceTests.swift
import XCTest
import SwiftData
@testable import RodaAiCore

final class PerformanceTests: XCTestCase {

    // MARK: - File Processing Performance

    func testTXTExtractionPerformance() throws {
        let processor = FileProcessor()
        let fixtureURL = Bundle.module.resourceURL!
            .appendingPathComponent("Fixtures/Files/sample.txt")

        measure {
            _ = try? Task {
                try await processor.extractText(from: fixtureURL)
            }
        }
        // Baseline: < 50ms for < 1MB file
    }

    func testCSVExtractionPerformance() throws {
        let processor = FileProcessor()
        let fixtureURL = Bundle.module.resourceURL!
            .appendingPathComponent("Fixtures/Files/sample.csv")

        measure {
            _ = try? Task {
                try await processor.extractText(from: fixtureURL)
            }
        }
    }

    // MARK: - Mock Inference Performance (token throughput)

    func testMockInferenceTokenThroughput() async throws {
        let mock = MockInferenceProvider()
        await mock.setTokenDelay(.zero)
        let tokens = (0..<100).map { "token\($0)" }
        await mock.setGenerateResponses(tokens)
        try await mock.loadModel(identifier: "test")

        let messages = [ChatMessage(role: .user, content: "Teste")]
        let config = GenerationConfig()

        let start = ContinuousClock().now
        let stream = await mock.generate(messages: messages, config: config)
        var count = 0
        for try await _ in stream {
            count += 1
        }
        let elapsed = ContinuousClock().now - start

        XCTAssertEqual(count, 100)
        // Mock with zero delay should complete in < 100ms
        XCTAssertLessThan(elapsed, .milliseconds(100),
                          "100 tokens with zero delay must complete in < 100ms")
    }

    // MARK: - State Machine Transition Performance

    func testVoiceStateTransitionPerformance() {
        measure {
            for _ in 0..<10_000 {
                var state = VoiceState.idle
                try? state.transition(.startVoice)
                try? state.transition(.partialTranscript("Ola"))
                try? state.transition(.speechDone(transcript: "Ola"))
                try? state.transition(.responseReady(text: "Resposta"))
                try? state.transition(.speechDone(transcript: ""))
            }
        }
        // 10k full cycles should complete in < 100ms
    }

    func testChatStateTransitionPerformance() {
        measure {
            for _ in 0..<10_000 {
                var state = ChatState.idle
                try? state.transition(.send(modelIdentifier: "test"))
                try? state.transition(.firstToken)
                for _ in 0..<10 {
                    try? state.transition(.tokenReceived)
                }
                try? state.transition(.finished(durationMs: 100))
                try? state.transition(.reset)
            }
        }
    }

    // MARK: - App Startup Proxy

    func testUserPreferencesLoadPerformance() throws {
        let schema = Schema([UserPreferences.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        measure {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<UserPreferences>()
            _ = try? context.fetch(descriptor)
        }
        // SwiftData fetch should complete in < 10ms
    }
}
