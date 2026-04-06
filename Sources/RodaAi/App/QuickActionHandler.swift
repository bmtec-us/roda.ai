// Sources/RodaAi/App/QuickActionHandler.swift
//
// Recebe Home Screen Quick Actions do iOS (long-press no icone do app)
// e dispatcha para a navegacao apropriada via @Observable state.
//
// Tipos de quick action declarados em App/Info.plist:
//   - com.bmtec.rodaai.voice    -> abre tab Voz
//   - com.bmtec.rodaai.newchat  -> abre tab Conversas + nova conversa
//
// Ref: intro.md secao 3.5 — "Home Screen Quick Actions".
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class QuickActionHandler {
    /// Tipo do quick action mais recente recebido.
    /// Views observam essa propriedade para reagir a navegacao.
    public var pendingAction: QuickActionType?

    public init() {}

    /// Processa um shortcut item recebido do iOS.
    /// Retornado pelo onContinueUserActivity ou launchOptions.
    public func handle(typeIdentifier: String) {
        switch typeIdentifier {
        case "com.bmtec.rodaai.voice":
            pendingAction = .voice
        case "com.bmtec.rodaai.newchat":
            pendingAction = .newChat
        default:
            break  // Ignora tipos desconhecidos
        }
    }

    /// Limpa a acao pendente apos ser processada pela view.
    public func clear() {
        pendingAction = nil
    }
}

/// Tipos de Quick Action suportados.
public enum QuickActionType: String, Sendable, Equatable {
    case voice
    case newChat
}
