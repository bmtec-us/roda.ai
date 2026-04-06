// Tests/RodaAiCoreTests/Utilities/RelativeDateFormatterTests.swift
import Testing
import Foundation
@testable import RodaAiCore

@Suite("RelativeDateFormatter")
struct RelativeDateFormatterTests {

    let formatter = RelativeDateFormatter()
    let now = Date()

    @Test("less than 1 minute shows Agora")
    func testAgora() {
        let date = now.addingTimeInterval(-30)
        let result = formatter.string(from: date, relativeTo: now)
        #expect(result == "Agora")
    }

    @Test("5 minutes ago shows 5 min atras")
    func testMinutesAgo() {
        let date = now.addingTimeInterval(-5 * 60)
        let result = formatter.string(from: date, relativeTo: now)
        #expect(result == "5 min atras")
    }

    @Test("same day shows Hoje with time")
    func testToday() {
        let calendar = Calendar.current
        // 2 hours ago, same day
        let date = now.addingTimeInterval(-2 * 60 * 60)
        // Only test if it's still the same day
        if calendar.isDate(date, inSameDayAs: now) {
            let result = formatter.string(from: date, relativeTo: now)
            #expect(result.hasPrefix("Hoje"))
        }
    }

    @Test("yesterday shows Ontem with time")
    func testYesterday() {
        let date = now.addingTimeInterval(-24 * 60 * 60)
        let calendar = Calendar.current
        if calendar.isDateInYesterday(date) {
            let result = formatter.string(from: date, relativeTo: now)
            #expect(result.hasPrefix("Ontem"))
        }
    }
}
