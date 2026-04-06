// Sources/RodaAi/App/ContentView.swift
import SwiftUI
import RodaAiCore

struct ContentView: View {
    var body: some View {
        #if os(iOS)
        TabView {
            Tab("Conversas", systemImage: "message.fill") {
                NavigationStack {
                    Text("Conversas — Fase 6")
                }
            }
            Tab("Modelos", systemImage: "cpu.fill") {
                NavigationStack {
                    Text("Modelos — Fase 5")
                }
            }
            Tab("Voz", systemImage: "mic.fill") {
                NavigationStack {
                    Text("Voz — Fase 9")
                }
            }
            Tab("Ajustes", systemImage: "gearshape.fill") {
                NavigationStack {
                    Text("Ajustes — Fase 10")
                }
            }
        }
        #elseif os(macOS)
        NavigationSplitView {
            List {
                NavigationLink("Conversas", value: "conversations")
                NavigationLink("Modelos", value: "models")
            }
            .navigationTitle("RodaAi")
        } content: {
            Text("Selecione uma conversa")
        } detail: {
            Text("Detalhes")
        }
        #endif
    }
}
