// Tests/RodaAiTests/Localization/LocalizationTests.swift
import XCTest
@testable import RodaAi
import RodaAiCore

final class LocalizationTests: XCTestCase {

    // MARK: - All required keys exist

    private let requiredKeys: [String] = [
        // Navegacao
        "tab.conversations", "tab.models", "tab.voice", "tab.settings",
        // Chat
        "chat.send", "chat.stop", "chat.newConversation", "chat.typing",
        "chat.placeholder",
        // Modelos
        "model.download", "model.downloading", "model.downloaded", "model.delete",
        "model.loadingModel",
        // Ratings
        "rating.excellent", "rating.good", "rating.fair", "rating.toValidate",
        // Erros
        "error.insufficientMemory", "error.modelNotFound", "error.networkUnavailable",
        "error.insufficientStorage", "error.downloadFailed",
        // Onboarding
        "onboarding.welcome.title", "onboarding.welcome.subtitle",
        "onboarding.model.title", "onboarding.model.subtitle",
        "onboarding.chat.title", "onboarding.chat.subtitle",
        "onboarding.ready.title", "onboarding.ready.button",
        // Settings
        "settings.defaultModel", "settings.systemPrompt", "settings.temperature",
        "settings.voiceEnabled", "settings.appearance", "settings.storage",
        "settings.version",
    ]

    func testAllRequiredKeysExistInPortuguese() {
        let bundle = Bundle(for: type(of: self))
        // Load pt-BR localization
        guard let ptPath = bundle.path(forResource: "pt-BR", ofType: "lproj"),
              let ptBundle = Bundle(path: ptPath) else {
            XCTFail("pt-BR localization bundle not found")
            return
        }
        for key in requiredKeys {
            let localized = ptBundle.localizedString(forKey: key, value: "NOT_FOUND", table: nil)
            XCTAssertNotEqual(localized, "NOT_FOUND", "Missing pt-BR translation for key: '\(key)'")
        }
    }

    func testAllRequiredKeysExistInEnglish() {
        let bundle = Bundle(for: type(of: self))
        guard let enPath = bundle.path(forResource: "en", ofType: "lproj"),
              let enBundle = Bundle(path: enPath) else {
            XCTFail("en localization bundle not found")
            return
        }
        for key in requiredKeys {
            let localized = enBundle.localizedString(forKey: key, value: "NOT_FOUND", table: nil)
            XCTAssertNotEqual(localized, "NOT_FOUND", "Missing en translation for key: '\(key)'")
        }
    }

    func testNoMissingTranslationsBetweenLanguages() {
        let bundle = Bundle(for: type(of: self))
        guard let ptPath = bundle.path(forResource: "pt-BR", ofType: "lproj"),
              let ptBundle = Bundle(path: ptPath),
              let enPath = bundle.path(forResource: "en", ofType: "lproj"),
              let enBundle = Bundle(path: enPath) else {
            XCTFail("Localization bundles not found")
            return
        }
        for key in requiredKeys {
            let pt = ptBundle.localizedString(forKey: key, value: "NOT_FOUND", table: nil)
            let en = enBundle.localizedString(forKey: key, value: "NOT_FOUND", table: nil)
            XCTAssertNotEqual(pt, "NOT_FOUND", "pt-BR missing: \(key)")
            XCTAssertNotEqual(en, "NOT_FOUND", "en missing: \(key)")
        }
    }

    func testPortugueseStringsAreNotEmpty() {
        let bundle = Bundle(for: type(of: self))
        guard let ptPath = bundle.path(forResource: "pt-BR", ofType: "lproj"),
              let ptBundle = Bundle(path: ptPath) else {
            XCTFail("pt-BR localization bundle not found")
            return
        }
        for key in requiredKeys {
            let localized = ptBundle.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertFalse(localized.isEmpty, "pt-BR translation for '\(key)' must not be empty")
        }
    }

    func testErrorMessagesAreInPortuguese() {
        // Verify error types from error-types.md produce pt-BR messages
        let memError = InferenceError.insufficientMemory(required: 8_589_934_592, available: 4_294_967_296)
        let desc = memError.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Memoria") || desc.contains("memória") || desc.contains("insuficiente"),
                      "Error description must be in Portuguese: got '\(desc)'")
    }
}
