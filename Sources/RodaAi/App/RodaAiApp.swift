// Sources/RodaAi/App/RodaAiApp.swift
import SwiftUI

@main
struct RodaAiApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dependencies)
                .modelContainer(dependencies.modelContainer)
        }
    }
}
