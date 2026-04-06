// Sources/RodaAi/App/ContentView.swift
import SwiftUI
import SwiftData
import RodaAiCore

struct ContentView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.modelContext) private var modelContext

    // Query para detectar se onboarding ja foi completado
    @Query private var preferences: [UserPreferences]

    private var hasCompletedOnboarding: Bool {
        preferences.first?.hasCompletedOnboarding ?? false
    }

    var body: some View {
        if hasCompletedOnboarding {
            mainAppView
        } else {
            OnboardingView()
        }
    }

    // MARK: - Main App (post-onboarding)

    @ViewBuilder
    private var mainAppView: some View {
        #if os(iOS)
        iOSTabs
        #elseif os(macOS)
        macOSSplitView
        #endif
    }

    #if os(iOS)
    @State private var selectedTab: Int = 0

    private var iOSTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Conversas", systemImage: "message.fill", value: 0) {
                conversationsTab
            }
            Tab("Modelos", systemImage: "cpu.fill", value: 1) {
                ModelGalleryView(modelManager: deps.modelManager)
            }
            Tab("Voz", systemImage: "mic.fill", value: 2) {
                NavigationStack {
                    VoiceModeView(voiceService: deps.voiceService)
                        .navigationTitle("Voz")
                }
            }
            Tab("Ajustes", systemImage: "gearshape.fill", value: 3) {
                SettingsView(modelContext: deps.modelContainer.mainContext)
            }
        }
    }

    private var conversationsTab: some View {
        NavigationStack {
            ConversationsContainer()
                .environment(deps)
        }
    }
    #endif

    #if os(macOS)
    @State private var macNavTarget: MacNavTarget? = .conversations

    private var macOSSplitView: some View {
        NavigationSplitView {
            List(selection: $macNavTarget) {
                Label("Conversas", systemImage: "message.fill")
                    .tag(MacNavTarget.conversations)
                Label("Modelos", systemImage: "cpu.fill")
                    .tag(MacNavTarget.models)
                Label("Voz", systemImage: "mic.fill")
                    .tag(MacNavTarget.voice)
                Label("Ajustes", systemImage: "gearshape.fill")
                    .tag(MacNavTarget.settings)
            }
            .navigationTitle("RodaAi")
            .listStyle(.sidebar)
        } detail: {
            macOSDetail
        }
    }

    @ViewBuilder
    private var macOSDetail: some View {
        switch macNavTarget ?? .conversations {
        case .conversations:
            ConversationsContainer()
                .environment(deps)
        case .models:
            ModelGalleryView(modelManager: deps.modelManager)
        case .voice:
            VoiceModeView(voiceService: deps.voiceService)
                .navigationTitle("Voz")
        case .settings:
            SettingsView(modelContext: deps.modelContainer.mainContext)
        }
    }
    #endif
}

#if os(macOS)
private enum MacNavTarget: Hashable {
    case conversations, models, voice, settings
}
#endif

// MARK: - Conversations Container
//
// Container que combina ConversationListView (master) + ChatView (detail),
// mantendo um unico ChatViewModel reutilizado ao trocar de conversa.
// Wrapa a logica de "criar nova" / "abrir existente" para ambos os layouts.

struct ConversationsContainer: View {
    @Environment(AppDependencies.self) private var deps
    @State private var chatViewModel: ChatViewModel?
    @State private var showingList: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if let vm = chatViewModel {
                ChatView(viewModel: vm)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                startNew()
                            } label: {
                                Label("Nova Conversa", systemImage: "square.and.pencil")
                            }
                        }
                        ToolbarItem(placement: .navigation) {
                            Button {
                                showingList = true
                            } label: {
                                Label("Historico", systemImage: "list.bullet")
                            }
                        }
                    }
                    .sheet(isPresented: $showingList) {
                        conversationListSheet
                    }
            } else {
                ProgressView("Inicializando...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if chatViewModel == nil {
                chatViewModel = ChatViewModel(
                    inferenceProvider: deps.inferenceProvider,
                    repository: deps.conversationRepository
                )
            }
        }
    }

    private var conversationListSheet: some View {
        NavigationStack {
            ConversationListView(
                repository: deps.conversationRepository,
                onNewConversation: {
                    startNew()
                    showingList = false
                },
                onSelectConversation: { summary in
                    Task {
                        await chatViewModel?.loadConversation(id: summary.id)
                        showingList = false
                    }
                }
            )
        }
    }

    private func startNew() {
        chatViewModel?.startNewConversation()
    }
}
