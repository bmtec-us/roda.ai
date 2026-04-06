// Tests/RodaAiCoreTests/Data/PersistenceIntegrationTests.swift
import Testing
import SwiftData
import Foundation
@testable import RodaAiCore

@Suite("Persistence Integration")
struct PersistenceIntegrationTests {

    private func makeRepository() throws -> ConversationRepository {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self,
            configurations: config
        )
        return ConversationRepository(modelContainer: container)
    }

    @Test("send message creates conversation and persists messages")
    @MainActor
    func testSendMessagePersists() async throws {
        let repo = try makeRepository()
        let mockProvider = MockInferenceProvider()
        await mockProvider.setGenerateResponses(["Ola", " mundo"])

        let vm = ChatViewModel(
            inferenceProvider: mockProvider,
            repository: repo
        )
        await vm.send("Oi")

        // Verify persistence
        let conversations = try await repo.fetch(matching: nil)
        #expect(conversations.count == 1)

        let messages = try await repo.fetchMessages(for: conversations[0].id)
        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[0].content == "Oi")
        #expect(messages[1].role == .assistant)
        #expect(messages[1].content == "Ola mundo")
    }

    @Test("load existing conversation restores message history")
    @MainActor
    func testLoadConversation() async throws {
        let repo = try makeRepository()

        // Create conversation with messages directly
        let summary = try await repo.create(
            title: "Conversa existente",
            modelIdentifier: "gemma"
        )
        try await repo.addMessage(
            to: summary.id, role: .user,
            content: "Pergunta 1", modelIdentifier: nil
        )
        try await repo.addMessage(
            to: summary.id, role: .assistant,
            content: "Resposta 1", modelIdentifier: "gemma"
        )

        // Load in ViewModel
        let mockProvider = MockInferenceProvider()
        let vm = ChatViewModel(
            inferenceProvider: mockProvider,
            repository: repo
        )
        await vm.loadConversation(id: summary.id)

        #expect(vm.messages.count == 2)
        #expect(vm.messages[0].content == "Pergunta 1")
        #expect(vm.messages[1].content == "Resposta 1")
    }

    @Test("search finds conversations by title")
    func testSearchConversations() async throws {
        let repo = try makeRepository()
        _ = try await repo.create(
            title: "Conversa sobre Python",
            modelIdentifier: "gemma"
        )
        _ = try await repo.create(
            title: "Receita de pao",
            modelIdentifier: "gemma"
        )
        _ = try await repo.create(
            title: "Tutorial Python avancado",
            modelIdentifier: "gemma"
        )

        let results = try await repo.fetch(matching: "Python")

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.title.contains("Python") })
    }

    @Test("delete conversation removes it from persistence")
    func testDeleteConversation() async throws {
        let repo = try makeRepository()
        let summary = try await repo.create(
            title: "Para deletar",
            modelIdentifier: "gemma"
        )

        try await repo.delete(id: summary.id)

        let remaining = try await repo.fetch(matching: nil)
        #expect(remaining.isEmpty)

        // Trying to fetch messages should throw
        do {
            _ = try await repo.fetchMessages(for: summary.id)
            Issue.record("Expected PersistenceError.conversationNotFound")
        } catch let error as PersistenceError {
            if case .conversationNotFound = error {
                // OK
            } else {
                Issue.record("Expected .conversationNotFound but got \(error)")
            }
        }
    }
}
