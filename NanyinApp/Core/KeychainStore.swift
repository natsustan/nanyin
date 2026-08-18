//
//  KeychainStore.swift
//  Nanyin
//

import Foundation
import Security

/// Minimal Keychain wrapper for the OAuth tokens.
enum KeychainStore {
    private static let service = "com.nanyin.app.spotify"

    struct KeychainError: Error, LocalizedError {
        let operation: String
        let key: String
        let status: OSStatus

        var errorDescription: String? {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain \(operation) failed for \(key): \(detail)"
        }
    }

    static func setString(_ value: String, forKey key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let updates: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(operation: "update", key: key, status: updateStatus)
        }

        var attributes = query
        attributes.merge(updates) { _, new in new }
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(operation: "add", key: key, status: addStatus)
        }
    }

    static func string(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError(operation: "read", key: key, status: status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(operation: "decode", key: key, status: errSecDecode)
        }
        return value
    }

    static func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(operation: "delete", key: key, status: status)
        }
    }
}

extension KeychainStore {
    /// Stable per-install Spotify Connect device id (created once).
    static func spotifyDeviceId() throws -> String {
        if let existing = try string(forKey: "device_id") {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 10)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else {
            throw KeychainError(operation: "generate", key: "device_id", status: randomStatus)
        }
        let id = bytes.map { String(format: "%02x", $0) }.joined()
        try setString(id, forKey: "device_id")
        return id
    }
}
