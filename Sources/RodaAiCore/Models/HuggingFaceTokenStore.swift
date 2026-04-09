// Sources/RodaAiCore/Models/HuggingFaceTokenStore.swift
//
// Secure storage for the user's Hugging Face access token.
//
// Uses the iOS/macOS Keychain so the token is:
//   - encrypted at rest by the OS
//   - tied to the app's bundle identifier (not visible to other apps)
//   - excluded from iCloud Keychain sync (kSecAttrSynchronizable = false)
//     so the token doesn't roam to devices where the user may not want it
//   - available only when the device is unlocked after first unlock
//     (kSecAttrAccessibleAfterFirstUnlock) so background downloads can
//     still proceed after a reboot without user interaction
//
// The token is OPTIONAL. RodaAi downloads work without it, but they fall
// back to anonymous HTTP which hits Hugging Face's aggressive rate limits
// after a handful of requests. A personal HF token (read scope is enough)
// lifts the limit dramatically.
//
// Get a token at: https://huggingface.co/settings/tokens

import Foundation
import Security

public struct HuggingFaceTokenStore: Sendable {

    /// Keychain service identifier. Scoped to RodaAi so other apps on
    /// the same device can't see or collide with this item.
    private static let service = "com.bmtec.rodaai.huggingface"
    private static let account = "access-token"

    public init() {}

    /// Returns the stored token, or `nil` if none is set.
    public func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : token
    }

    /// Stores a new token, replacing any existing value. Pass an empty or
    /// whitespace-only string to remove the token entirely.
    @discardableResult
    public func save(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return clear()
        }

        guard let data = trimmed.data(using: .utf8) else { return false }

        // Try update first; if no existing item, add.
        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: false
        ]

        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        var addQuery = searchQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        addQuery[kSecAttrSynchronizable as String] = false
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the token from the Keychain. Returns true even when there
    /// was nothing to remove (idempotent).
    @discardableResult
    public func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// True if a non-empty token is currently stored.
    public var hasToken: Bool {
        load() != nil
    }

    /// Exports the stored token as the `HF_TOKEN` process environment
    /// variable so third-party Swift HuggingFace clients (swift-huggingface,
    /// used internally by mlx-audio-swift for Kokoro downloads, and any
    /// future SDK that follows the same convention) pick it up automatically.
    ///
    /// Call once at app startup and again whenever the user saves or clears
    /// the token so the change takes effect without an app restart.
    /// No-op when no token is stored (env var is cleared).
    public func applyToEnvironment() {
        if let token = load() {
            setenv("HF_TOKEN", token, 1)
        } else {
            unsetenv("HF_TOKEN")
        }
    }
}
