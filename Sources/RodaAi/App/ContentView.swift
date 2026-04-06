// Sources/RodaAi/App/ContentView.swift
import SwiftUI
import SwiftData
import RodaAiCore

struct ContentView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(QuickActionHandler.self) private var quickActions
    @Environment(\.modelContext) private var modelContext

    // Query para detectar se onboarding ja foi completado.
    // Usa `contains` em vez de `first?` — defensivo contra multiplas rows
    // que podem existir de versoes anteriores buggadas do OnboardingView.
    @Query private var preferences: [UserPreferences]

    private var hasCompletedOnboarding: Bool {
        preferences.contains { $0.hasCompletedOnboarding }
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainAppView
            } else {
                OnboardingView()
            }
        }
        .onChange(of: quickActions.pendingAction) { _, action in
            handleQuickAction(action)
        }
    }

    /// Reage a Home Screen Quick Actions (iOS) navegando para a tab apropriada.
    private func handleQuickAction(_ action: QuickActionType?) {
        guard let action else { return }
        #if os(iOS)
        switch action {
        case .voice:
            selectedTab = 2  // Tab Voz
        case .newChat:
            selectedTab = 0  // Tab Conversas (e starta nova via state)
        }
        #endif
        quickActions.clear()
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
            Tab("tab.conversations", systemImage: "message.fill", value: 0) {
                conversationsTab
            }
            Tab("tab.models", systemImage: "cpu.fill", value: 1) {
                ModelGalleryView(modelManager: deps.modelManager)
            }
            Tab("tab.voice", systemImage: "mic.fill", value: 2) {
                NavigationStack {
                    VoiceModeView(voiceService: deps.voiceService)
                        .navigationTitle("tab.voice")
                }
            }
            Tab("tab.settings", systemImage: "gearshape.fill", value: 3) {
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
                Label("tab.conversations", systemImage: "message.fill")
                    .tag(MacNavTarget.conversations)
                Label("tab.models", systemImage: "cpu.fill")
                    .tag(MacNavTarget.models)
                Label("tab.voice", systemImage: "mic.fill")
                    .tag(MacNavTarget.voice)
                Label("tab.settings", systemImage: "gearshape.fill")
                    .tag(MacNavTarget.settings)
            }
            .navigationTitle("app.name")
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
                .navigationTitle("tab.voice")
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
    // Default false — sheet so abre quando usuario toca botao Historico.
    // Antes (bug): default true abria sheet vazio em todo launch.
    @State private var showingList: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if let vm = chatViewModel {
                ChatView(viewModel: vm)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                startNew()
                            } label: {
                                Label("chat.action.newConversation", systemImage: "square.and.pencil")
                            }
                        }
                        ToolbarItem(placement: .navigation) {
                            Button {
                                showingList = true
                            } label: {
                                Label("chat.action.history", systemImage: "list.bullet")
                            }
                        }
                    }
                    .sheet(isPresented: $showingList) {
                        conversationListSheet
                    }
            } else {
                ProgressView("app.initializing")
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
