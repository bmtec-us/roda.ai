// Sources/RodaAi/Integrations/Widgets/RodaAiControlWidget.swift
import WidgetKit
import SwiftUI

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
    static var title: LocalizedStringResource = "Abrir RodaAi"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
