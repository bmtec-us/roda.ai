// Sources/RodaAi/App/ContentView.swift
import SwiftUI
import SwiftData
import RodaAiCore

struct ContentView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(QuickActionHandler.self) private var quickActions
    @Environment(\.modelContext) private var modelContext

    @Query private var preferences: [UserPreferences]

    private var hasCompletedOnboarding: Bool {
        preferences.contains { $0.hasCompletedOnboarding }
    }

    private var colorScheme: ColorScheme? {
        guard let pref = preferences.first else { return nil }
        switch pref.appearanceMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainAppView
            } else {
                OnboardingView()
            }
        }
        .background(ColorPalette.surface.ignoresSafeArea())
        .tint(ColorPalette.accent)
        .preferredColorScheme(colorScheme)
        .onChange(of: quickActions.pendingAction) { _, action in
            handleQuickAction(action)
        }
    }

    private func handleQuickAction(_ action: QuickActionType?) {
        guard let action else { return }
        #if os(iOS)
        switch action {
        case .voice:
            selectedTab = 2
        case .newChat:
            selectedTab = 0
        }
        #endif
        quickActions.clear()
    }

    // MARK: - Main App

    @ViewBuilder
    private var mainAppView: some View {
        #if os(iOS)
        iOSTabs
        #elseif os(macOS)
        macOSSplitView
        #endif
    }

    // MARK: - iOS (Glass Tab Bar auto-applied by iOS 26)

    #if os(iOS)
    @State private var selectedTab: Int = 0

    private var iOSTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("tab.conversations", systemImage: "message.fill", value: 0) {
                conversationsTab
            }
            Tab("tab.models", systemImage: "cpu.fill", value: 1) {
                ModelGalleryView(modelManager: deps.modelManager, textToSpeechService: deps.textToSpeechService)
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
        // iOS 26: TabView automatically gets glass floating pill tab bar.
        // No extra code needed — the system handles glass rendering.
    }

    private var conversationsTab: some View {
        NavigationStack {
            ConversationsContainer()
                .environment(deps)
        }
    }
    #endif

    // MARK: - macOS (Glass Sidebar auto-applied by macOS 26)

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
            ModelGalleryView(modelManager: deps.modelManager, textToSpeechService: deps.textToSpeechService)
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

struct ConversationsContainer: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @State private var chatViewModel: ChatViewModel?
    @State private var showingList: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if let vm = chatViewModel {
                ChatView(
                    viewModel: vm,
                    chatFontSize: preferences.first?.chatFontSize ?? .system,
                    onResponseLengthChange: { newLength in
                        persistResponseLengthPreference(newLength)
                    }
                )
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
                    repository: deps.conversationRepository,
                    responseStyle: preferences.first?.responseStyle ?? .natural,
                    responseLength: preferences.first?.responseLength ?? .normal,
                    systemPrompt: preferences.first?.systemPrompt ?? "",
                    maxResponseTokens: preferences.first?.maxTokens ?? 2048
                )
            }
        }
        .onChange(of: preferences.first?.responseStyle) { _, newStyle in
            guard let newStyle else { return }
            chatViewModel?.responseStyle = newStyle
        }
        .onChange(of: preferences.first?.responseLength) { _, newLength in
            guard let newLength else { return }
            chatViewModel?.responseLength = newLength
        }
        .onChange(of: preferences.first?.systemPrompt) { _, newPrompt in
            chatViewModel?.systemPrompt = newPrompt ?? ""
        }
        .onChange(of: preferences.first?.maxTokens) { _, newMaxTokens in
            chatViewModel?.maxResponseTokens = newMaxTokens ?? 2048
        }
    }

    private var conversationListSheet: some View {
        NavigationStack {
            ConversationListView(
                repository: deps.conversationRepository,
                activeConversationId: chatViewModel?.currentConversationId,
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("conversation.action.done") {
                        showingList = false
                    }
                }
            }
        }
    }

    private func startNew() {
        chatViewModel?.startNewConversation()
    }

    private func persistResponseLengthPreference(_ value: ResponseLengthPreference) {
        do {
            if let existing = preferences.first {
                if existing.responseLength != value {
                    existing.responseLength = value
                    try modelContext.save()
                }
            } else {
                let prefs = UserPreferences()
                prefs.responseLength = value
                modelContext.insert(prefs)
                try modelContext.save()
            }
        } catch {
            // Non-fatal: keep chat behavior even if persistence fails.
            print("Failed to persist response length preference: \(error)")
        }
    }
}
