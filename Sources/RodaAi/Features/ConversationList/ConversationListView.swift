// Sources/RodaAi/Features/ConversationList/ConversationListView.swift
import SwiftUI

struct ConversationListView: View {
    var body: some View {
        List {
            Text("Nenhuma conversa ainda")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Conversas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nova Conversa", systemImage: "plus") {
                    // Implementado na Fase 6
                }
            }
        }
    }
}
