// Tests/RodaAiCoreTests/Data/ConversationRepositoryTests.swift
import Testing
import SwiftData
import Foundation
@testable import RodaAiCore

@Suite("ConversationRepository")
struct ConversationRepositoryTests {

    /// Cria container in-memory para cada teste (ref: mock-strategy.md regra 5)
    private func makeRepository() throws -> ConversationRepository {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self,
            configurations: config
        )
        return ConversationRepository(modelContainer: container)
    }

    // MARK: - Create

    @Test("create returns conversation with title and model identifier")
    func testCreate() async throws {
        let repo = try makeRepository()
        let summary = try await repo.create(
            title: "Minha conversa",
            modelIdentifier: "gemma-4-e4b"
        )

        #expect(summary.title == "Minha conversa")
        #expect(summary.modelIdentifier == "gemma-4-e4b")
        #expect(summary.id != UUID())
    }

    @Test("create sets createdAt and updatedAt to now")
    func testCreateTimestamps() async throws {
        let before = Date()
        let repo = try makeRepository()
        let summary = try await repo.create(
            title: "Test",
            modelIdentifier: "gemma-4-e4b"
        )
        let after = Date()

        #expect(summary.createdAt >= before)
        #expect(summary.createdAt <= after)
        #expect(summary.updatedAt >= before)
        #expect(summary.updatedAt <= after)
    }

    // MARK: - Fetch

    @Test("fetch returns all conversations ordered by updatedAt descending")
    func testFetchOrdered() async throws {
        let repo = try makeRepository()
        _ = try await repo.create(title: "Primeira", modelIdentifier: "gemma")
        try await Task.sleep(for: .milliseconds(10))
        _ = try await repo.create(title: "Segunda", modelIdentifier: "gemma")
        try await Task.sleep(for: .milliseconds(10))
        _ = try await repo.create(title: "Terceira", modelIdentifier: "gemma")

        let results = try await repo.fetch(matching: nil)

        #expect(results.count == 3)
        #expect(results[0].title == "Terceira")
        #expect(results[1].title == "Segunda")
        #expect(results[2].title == "Primeira")
    }

    @Test("fetch with query filters by title")
    func testFetchWithQuery() async throws {
        let repo = try makeRepository()
        _ = try await repo.create(title: "Conversa sobre Swift", modelIdentifier: "gemma")
        _ = try await repo.create(title: "Receita de bolo", modelIdentifier: "gemma")
        _ = try await repo.create(title: "Codigo Swift avancado", modelIdentifier: "gemma")

        let results = try await repo.fetch(matching: "Swift")

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.title.contains("Swift") })
    }

    @Test("fetch with no matches returns empty array")
    func testFetchNoMatches() async throws {
        let repo = try makeRepository()
        _ = try await repo.create(title: "Conversa teste", modelIdentifier: "gemma")

        let results = try await repo.fetch(matching: "inexistente")

        #expect(results.isEmpty)
    }

    @Test("fetchCount returns correct count without loading all data")
    func testFetchCount() async throws {
        let repo = try makeRepository()
        _ = try await repo.create(title: "A", modelIdentifier: "gemma")
        _ = try await repo.create(title: "B", modelIdentifier: "gemma")
        _ = try await repo.create(title: "C", modelIdentifier: "gemma")

        let count = try await repo.fetchCount()

        #expect(count == 3)
    }

    // MARK: - Update

    @Test("addMessage adds message to conversation and updates updatedAt")
    func testAddMessage() async throws {
        let repo = try makeRepository()
        let summary = try await repo.create(
            title: "Test", modelIdentifier: "gemma"
        )
        let originalUpdatedAt = summary.updatedAt

        try await Task.sleep(for: .milliseconds(10))

        try await repo.addMessage(
            to: summary.id,
            role: .user,
            content: "Ola mundo",
            modelIdentifier: "gemma-4-e4b"
        )

        let messages = try await repo.fetchMessages(for: summary.id)
        #expect(messages.count == 1)
        #expect(messages[0].content == "Ola mundo")
        #expect(messages[0].role == .user)

        // updatedAt should be newer
        let updated = try await repo.fetch(matching: nil)
        #expect(updated[0].updatedAt > originalUpdatedAt)
    }

    // MARK: - Delete

    @Test("delete removes conversation")
    func testDelete() async throws {
        let repo = try makeRepository()
        let summary = try await repo.create(
            title: "Para deletar", modelIdentifier: "gemma"
        )

        try await repo.delete(id: summary.id)

        let results = try await repo.fetch(matching: nil)
        #expect(results.isEmpty)
    }

    @Test("delete nonexistent conversation throws conversationNotFound")
    func testDeleteNonexistent() async {
        do {
            let repo = try makeRepository()
            try await repo.delete(id: UUID())
            Issue.record("Expected PersistenceError.conversationNotFound")
        } catch let error as PersistenceError {
            if case .conversationNotFound = error {
                // OK
            } else {
                Issue.record("Expected .conversationNotFound but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Auto-Titulo

    @Test("auto-generates title from first user message")
    func testAutoTitle() async throws {
        let repo = try makeRepository()
        let summary = try await repo.create(
            title: "", modelIdentifier: "gemma"
        )

        try await repo.addMessage(
            to: summary.id,
            role: .user,
            content: "Explique como funciona o protocolo TCP/IP em redes de computadores",
            modelIdentifier: nil
        )

        let autoTitle = try await repo.generateAutoTitle(for: summary.id)

        // Title should be truncated version of first message
        #expect(autoTitle.count <= 50)
        #expect(autoTitle.hasPrefix("Explique como"))
    }

    @Test("auto-title returns default when no user messages exist")
    func testAutoTitleNoMessages() async throws {
        let repo = try makeRepository()
        let summary = try await repo.create(
            title: "", modelIdentifier: "gemma"
        )

        let autoTitle = try await repo.generateAutoTitle(for: summary.id)

        #expect(autoTitle == "Nova conversa")
    }

    // MARK: - Concorrencia (ref: concurrency-model.md)

    @Test("concurrent creates do not corrupt data")
    func testConcurrentCreates() async throws {
        let repo = try makeRepository()

        try await withThrowingTaskGroup(of: ConversationSummary.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try await repo.create(
                        title: "Conversa \(i)",
                        modelIdentifier: "gemma"
                    )
                }
            }
            for try await _ in group { }
        }

        let count = try await repo.fetchCount()
        #expect(count == 10)
    }

    @Test("concurrent read and write do not crash")
    func testConcurrentReadWrite() async throws {
        let repo = try makeRepository()
        _ = try await repo.create(title: "Seed", modelIdentifier: "gemma")

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Writer
            group.addTask {
                for i in 0..<5 {
                    _ = try await repo.create(
                        title: "Write \(i)",
                        modelIdentifier: "gemma"
                    )
                }
            }
            // Reader
            group.addTask {
                for _ in 0..<5 {
                    _ = try await repo.fetch(matching: nil)
                }
            }
            try await group.waitForAll()
        }

        let count = try await repo.fetchCount()
        #expect(count == 6) // 1 seed + 5 writes
    }
}
