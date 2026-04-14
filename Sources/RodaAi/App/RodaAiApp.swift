// Sources/RodaAi/App/RodaAiApp.swift
import SwiftUI
import RodaAiCore
#if canImport(UIKit)
import UIKit
#endif

@main
struct RodaAiApp: App {
    /// Applies the stored `AppLanguage` preference to the process's
    /// `AppleLanguages` user default BEFORE any SwiftUI views get
    /// built, so the first paint reads the correct localizations.
    /// Runs as the first side-effect at @main type resolution.
    private static let _languageBootstrap: Void = {
        let raw = UserDefaults.standard.string(forKey: AppLanguage.userDefaultsKey) ?? AppLanguage.system.rawValue
        let language = AppLanguage(rawValue: raw) ?? .system
        if let override = language.appleLanguagesValue {
            UserDefaults.standard.set(override, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }()

    @State private var dependencies: AppDependencies = {
        _ = RodaAiApp._languageBootstrap
        return AppDependencies()
    }()
    @State private var quickActionHandler = QuickActionHandler()

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dependencies)
                .environment(quickActionHandler)
                .modelContainer(dependencies.modelContainer)
                .onAppear {
                    #if canImport(UIKit)
                    // Conecta AppDelegate ao handler observavel via shared state
                    AppDelegate.quickActionHandler = quickActionHandler
                    // Processa launch shortcut se houver
                    if let shortcut = AppDelegate.launchShortcut {
                        quickActionHandler.handle(typeIdentifier: shortcut.type)
                        AppDelegate.launchShortcut = nil
                    }
                    #endif
                }
        }
    }
}

#if canImport(UIKit)
/// AppDelegate adapter para receber UIApplicationShortcutItems.
/// SwiftUI App protocol nao expoe diretamente o callback de quick actions,
/// entao precisamos do classico adapter UIKit.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Quick action recebida no launch — processada apos o app aparecer.
    nonisolated(unsafe) static var launchShortcut: UIApplicationShortcutItem?
    /// Handler conectado pelo @main app via .onAppear.
    nonisolated(unsafe) static var quickActionHandler: QuickActionHandler?

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Captura shortcut de launch (se app estava fechado).
        if let shortcut = options.shortcutItem {
            Self.launchShortcut = shortcut
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        // App ja estava rodando — dispatcha imediatamente
        Task { @MainActor in
            Self.quickActionHandler?.handle(typeIdentifier: shortcutItem.type)
            completionHandler(true)
        }
    }
}
#endif
