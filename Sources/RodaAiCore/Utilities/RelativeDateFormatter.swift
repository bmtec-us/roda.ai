// Sources/RodaAiCore/Utilities/RelativeDateFormatter.swift
import Foundation

public struct RelativeDateFormatter: Sendable {

    public init() {}

    /// Formata data relativa em pt-BR
    /// - "Agora" (< 1 min)
    /// - "5 min atras" (< 1 hora)
    /// - "Hoje, 14:30" (hoje)
    /// - "Ontem, 09:15" (ontem)
    /// - "3 Abr" (esta semana / este ano)
    /// - "15 Mar 2026" (ano anterior)
    public func string(from date: Date, relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current
        let interval = now.timeIntervalSince(date)

        // Menos de 1 minuto
        if interval < 60 {
            return "Agora"
        }

        // Menos de 1 hora
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min atras"
        }

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "pt-BR")
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: date)

        // Hoje
        if calendar.isDate(date, inSameDayAs: now) {
            return "Hoje, \(timeString)"
        }

        // Ontem
        if calendar.isDateInYesterday(date) {
            return "Ontem, \(timeString)"
        }

        // Mesmo ano
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "pt-BR")

        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            dateFormatter.dateFormat = "d MMM"
            return dateFormatter.string(from: date)
        }

        // Ano diferente
        dateFormatter.dateFormat = "d MMM yyyy"
        return dateFormatter.string(from: date)
    }
}
