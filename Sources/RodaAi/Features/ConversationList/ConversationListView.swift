// Sources/RodaAi/Features/ConversationList/ConversationListView.swift
import SwiftUI
import RodaAiCore

struct ConversationListView: View {
    @State private var conversations: [ConversationSummary] = []
    @State private var searchText = ""
    @State private var selectedConversation: ConversationSummary?

    let repository: ConversationRepository
    let onNewConversation: () -> Void
    let onSelectConversation: (ConversationSummary) -> Void

    var body: some View {
        List {
            if conversations.isEmpty {
                ContentUnavailableView(
                    "Nenhuma conversa",
                    systemImage: "message",
                    description: Text("Toque + para iniciar uma nova conversa")
                )
            } else {
                ForEach(conversations) { conversation in
                    ConversationRow(conversation: conversation)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectConversation(conversation)
                        }
                }
                .onDelete(perform: deleteConversations)
            }
        }
        .navigationTitle("Conversas")
        .searchable(text: $searchText, prompt: "Buscar conversas...")
        .onChange(of: searchText) { _, query in
            Task { await loadConversations(matching: query) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nova Conversa", systemImage: "plus") {
                    onNewConversation()
                }
            }
        }
        .task {
            await loadConversations()
        }
    }

    private func loadConversations(matching query: String? = nil) async {
        do {
            let query = query?.isEmpty == true ? nil : query
            conversations = try await repository.fetch(matching: query)
        } catch {
            // Handle PersistenceError.fetchFailed
            conversations = []
        }
    }

    private func deleteConversations(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let conversation = conversations[index]
                try? await repository.delete(id: conversation.id)
            }
            await loadConversations()
        }
    }
}
