// Sources/RodaAi/Features/ConversationList/ConversationListView.swift
import SwiftUI
import RodaAiCore

struct ConversationListView: View {
    @State private var conversations: [ConversationSummary] = []
    @State private var searchText = ""
    @State private var selectedConversation: ConversationSummary?
    private let semanticSearch = SemanticSearchService()

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
                // System toolbar already provides Liquid Glass on iOS 26.
                // Don't double-glass with .glassProminent here.
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
            // Always fetch the full list (sorted by updatedAt desc) and let
            // the semantic search service re-rank when there's a query.
            // SQL substring filtering is too strict — "mistral MoE" wouldn't
            // match a conversation titled "Modelos esparsos".
            let all = try await repository.fetch(matching: nil)
            let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                conversations = all
            } else {
                conversations = await semanticSearch.rank(all, query: trimmed)
            }
        } catch {
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
