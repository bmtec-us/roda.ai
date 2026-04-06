// Tests/RodaAiTests/Localization/LocalizationTests.swift
//
// Verifica que todos os keys usados em views existem no Localizable.xcstrings
// com traducoes para pt-BR e en. Tambem verifica que as strings dos erros
// (LocalizedError) estao em portugues.
//
// Strategy: ler Localizable.xcstrings via Bundle como JSON e checar cada key
// requerida. Nao usa NSBundle.localizedString porque o test bundle pode nao
// ter as lprojs geradas em todos os contextos.
import XCTest
@testable import RodaAi
import RodaAiCore

final class LocalizationTests: XCTestCase {

    /// Todas as chaves usadas no codigo SwiftUI da app.
    /// Atualizada quando novas chaves sao adicionadas.
    private let requiredKeys: [String] = [
        // Tabs / nav
        "tab.conversations", "tab.models", "tab.voice", "tab.settings",
        "app.name", "app.initializing",

        // Chat
        "chat.title", "chat.assistant",
        "chat.empty.title", "chat.empty.subtitle",
        "chat.message.placeholder",
        "chat.action.send", "chat.action.stop", "chat.action.retry",
        "chat.action.newConversation", "chat.action.history",
        "chat.attachment.image",
        "chat.attachment.removeFile", "chat.attachment.removeImage",
        "chat.attachment.attachImage",

        // Model gallery
        "model.action.download", "model.action.activate",
        "model.action.deactivate", "model.action.delete",
        "model.status.active", "model.status.downloaded",
        "model.status.downloading", "model.status.available",
        "model.status.incompatible", "model.status.builtin",
        "model.search.placeholder", "model.filter.label",
        "model.filter.all", "model.filter.downloaded", "model.filter.compatible",
        "model.catalog.empty.title", "model.catalog.empty.description",
        "model.catalog.retry",
        "model.filter.empty.title", "model.filter.empty.description",
        "model.rating.excelente", "model.rating.bom",
        "model.rating.razoavel", "model.rating.limitado",

        // Voice
        "voice.state.idle", "voice.state.listening",
        "voice.state.processing", "voice.state.speaking", "voice.state.error",

        // Conversation list
        "conversation.list.title", "conversation.list.empty.title",
        "conversation.list.empty.description", "conversation.search.placeholder",
        "conversation.action.done",

        // Settings
        "settings.defaultModel", "settings.defaultModel.empty",
        "settings.temperature", "settings.systemPrompt",
        "settings.systemPrompt.placeholder", "settings.voiceEnabled",
        "settings.appearance", "settings.appearance.system",
        "settings.appearance.light", "settings.appearance.dark",
        "settings.storage.title", "settings.storage.label",
        "settings.storage.summary", "settings.storage.empty",
        "settings.storage.partial.title", "settings.storage.partial.subtitle",
        "settings.storage.deleteConfirm.title",
        "settings.storage.deleteConfirm.message",
        "settings.storage.deleteConfirm.cancel",
        "settings.storage.deleteConfirm.delete",
        "settings.version",

        // Onboarding
        "onboarding.continue", "onboarding.skip",
        "onboarding.welcome.title", "onboarding.welcome.subtitle",
        "onboarding.model.title", "onboarding.model.subtitle",
        "onboarding.chat.title", "onboarding.chat.subtitle",
        "onboarding.ready.title", "onboarding.ready.button",

        // Common
        "common.copy", "common.cancel", "common.error",
    ]

    // MARK: - xcstrings JSON loading

    private struct XCStringsFile: Decodable {
        let sourceLanguage: String
        let strings: [String: XCStringsEntry]
    }

    private struct XCStringsEntry: Decodable {
        let localizations: [String: XCStringsLocalization]?
    }

    private struct XCStringsLocalization: Decodable {
        let stringUnit: XCStringsUnit?
    }

    private struct XCStringsUnit: Decodable {
        let state: String
        let value: String
    }

    private func loadXCStrings() throws -> XCStringsFile {
        // Find the source xcstrings file relative to this test file
        let testFile = URL(fileURLWithPath: #filePath)
        // Tests/RodaAiTests/Localization/LocalizationTests.swift
        // -> Tests/ -> roda.ai/ -> Sources/RodaAi/Resources/Localizable.xcstrings
        let projectRoot = testFile
            .deletingLastPathComponent()  // Localization
            .deletingLastPathComponent()  // RodaAiTests
            .deletingLastPathComponent()  // Tests
        let xcstringsURL = projectRoot
            .appendingPathComponent("Sources/RodaAi/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: xcstringsURL)
        return try JSONDecoder().decode(XCStringsFile.self, from: data)
    }

    // MARK: - Tests

    func testXCStringsFileIsValid() throws {
        let file = try loadXCStrings()
        XCTAssertEqual(file.sourceLanguage, "pt-BR")
        XCTAssertGreaterThan(file.strings.count, 50, "Expected at least 50 keys")
    }

    func testAllRequiredKeysExistInXCStrings() throws {
        let file = try loadXCStrings()
        var missing: [String] = []
        for key in requiredKeys {
            if file.strings[key] == nil {
                missing.append(key)
            }
        }
        XCTAssertTrue(missing.isEmpty, "Missing keys in xcstrings: \(missing)")
    }

    func testAllRequiredKeysHavePtBRTranslation() throws {
        let file = try loadXCStrings()
        var missing: [String] = []
        for key in requiredKeys {
            guard let entry = file.strings[key] else {
                missing.append("\(key) (no entry)")
                continue
            }
            guard let pt = entry.localizations?["pt-BR"]?.stringUnit?.value, !pt.isEmpty else {
                missing.append("\(key) (no pt-BR)")
                continue
            }
        }
        XCTAssertTrue(missing.isEmpty, "Missing pt-BR translations: \(missing)")
    }

    func testAllRequiredKeysHaveEnglishTranslation() throws {
        let file = try loadXCStrings()
        var missing: [String] = []
        for key in requiredKeys {
            guard let entry = file.strings[key] else {
                missing.append("\(key) (no entry)")
                continue
            }
            guard let en = entry.localizations?["en"]?.stringUnit?.value, !en.isEmpty else {
                missing.append("\(key) (no en)")
                continue
            }
        }
        XCTAssertTrue(missing.isEmpty, "Missing en translations: \(missing)")
    }

    func testNoStaleKeysInXCStrings() throws {
        // Detecta chaves no xcstrings que NAO estao em requiredKeys.
        // Garante que nao acumulamos keys mortos.
        let file = try loadXCStrings()
        let extraKeys = Set(file.strings.keys).subtracting(Set(requiredKeys))
        XCTAssertTrue(
            extraKeys.isEmpty,
            "xcstrings has keys not used in code: \(extraKeys.sorted())"
        )
    }

    // MARK: - Error message localization

    func testErrorMessagesAreInPortuguese() {
        // Verify error types from error-types.md produce pt-BR messages
        let memError = InferenceError.insufficientMemory(
            required: 8_589_934_592,
            available: 4_294_967_296
        )
        let desc = memError.errorDescription ?? ""
        XCTAssertTrue(
            desc.contains("Memoria") || desc.contains("memória") || desc.contains("insuficiente"),
            "Error description must be in Portuguese: got '\(desc)'"
        )
    }

    func testDownloadErrorMessagesAreInPortuguese() {
        let netError = DownloadError.networkUnavailable
        let desc = netError.errorDescription ?? ""
        XCTAssertTrue(
            desc.contains("conexao") || desc.contains("internet") || desc.contains("rede"),
            "Network error must be in Portuguese: got '\(desc)'"
        )
    }
}
