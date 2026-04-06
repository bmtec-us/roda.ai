// Sources/RodaAi/Integrations/Widgets/RodaAiControlWidget.swift
import WidgetKit
import SwiftUI
import AppIntents

// ControlWidget e um framework iOS 18+/macOS 26+. Para targets que so iOS 18
// suporta, o widget e gateado por #available e nao compila no macOS abaixo de 26.
@available(iOS 18.0, macOS 26.0, *)
struct RodaAiControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.bmtec.rodaai.quick-chat") {
            ControlWidgetButton(action: OpenRodaAiIntent()) {
                Label("RodaAi", systemImage: "brain.head.profile")
            }
        }
        .displayName("RodaAi")
        .description("Abre o RodaAi rapidamente")
    }
}

struct OpenRodaAiIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir RodaAi"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
