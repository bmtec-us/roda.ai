// Sources/RodaAi/Features/ConversationList/ConversationListView.swift
import SwiftUI
import RodaAiCore

struct ConversationListView: View {
    @State private var conversations: [ConversationSummary] = []
    @State private var searchText = ""
    @State private var selectedConversation: ConversationSummary?

    let repository: ConversationRepository
    /// ID da conversa atualmente carregada no ChatViewModel — destacada com checkmark
    /// e fundo accent. Permite ao usuario ver de relance qual e a "atual" no historico.
    var activeConversationId: UUID? = nil
    let onNewConversation: () -> Void
    let onSelectConversation: (ConversationSummary) -> Void

    var body: some View {
        List {
            if conversations.isEmpty {
                ContentUnavailableView(
                    "conversation.list.empty.title",
                    systemImage: "message",
                    description: Text("conversation.list.empty.description")
                )
            } else {
                ForEach(conversations) { conversation in
                    HStack {
                        ConversationRow(conversation: conversation)
                        if conversation.id == activeConversationId {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ColorPalette.accent)
                                .accessibilityLabel("model.status.active")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectConversation(conversation)
                    }
                    .listRowBackground(
                        conversation.id == activeConversationId
                            ? ColorPalette.accent.opacity(0.1)
                            : Color.clear
                    )
                }
                .onDelete(perform: deleteConversations)
            }
        }
        .navigationTitle("conversation.list.title")
        .searchable(text: $searchText, prompt: Text("conversation.search.placeholder"))
        .onChange(of: searchText) { _, query in
            Task { await loadConversations(matching: query) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("chat.action.newConversation", systemImage: "plus") {
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
