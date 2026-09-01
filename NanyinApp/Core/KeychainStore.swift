//
//  KeychainStore.swift
//  Nanyin
//

import Darwin
import Foundation
import LocalAuthentication
import Security

/// Minimal Keychain wrapper for the OAuth tokens.
enum KeychainStore {
    private static let legacyService = "com.nanyin.app.spotify"

    /// Development signatures must never create credentials in the production
    /// namespace. A later Developer ID build would not satisfy their legacy
    /// Keychain ACL and macOS could otherwise offer an authorization prompt.
#if DEBUG
    private static let service = "com.nanyin.app.spotify.development.v2"
#else
    private static let service = "com.nanyin.app.spotify.v2"
#endif

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
        try disableUserInteraction()
        let data = Data(value.utf8)
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseAuthenticationContext as String: authenticationContext,
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
        try string(forKey: key, service: service)
    }

    private static func string(forKey key: String, service: String) throws -> String? {
        try disableUserInteraction()
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: authenticationContext,
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
        try disableUserInteraction()
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseAuthenticationContext as String: authenticationContext,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(operation: "delete", key: key, status: status)
        }
    }

    /// The modern authentication context covers Data Protection Keychain
    /// operations. This process-wide legacy switch additionally prevents the
    /// file-based Keychain ACL shim from presenting authorization UI. Never
    /// turn it back on: Nanyin treats inaccessible credentials as signed out.
    private static func disableUserInteraction() throws {
        let status = SecKeychainSetUserInteractionAllowed(false)
        guard status == errSecSuccess else {
            throw KeychainError(operation: "disable interaction", key: "*", status: status)
        }
    }
}

extension KeychainStore {
    private static let spotifyDeviceIdFileName = "spotify-device-id"

    /// Stable per-install Spotify Connect device id. It is not a secret, but it
    /// must survive restarts without ever being regenerated after a transient
    /// read failure, so keep it in an atomically written owner-only file.
    static func spotifyDeviceId(
        in applicationSupportDirectory: URL? = nil,
        legacyDeviceIdProvider: () throws -> String? = {
            try string(forKey: "device_id", service: legacyService)
        }
    ) throws -> String {
        let fileManager = FileManager.default
        let baseDirectory = try applicationSupportDirectory ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseDirectory.appendingPathComponent("Nanyin", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard let directoryStatus = try fileStatus(at: directory),
              directoryStatus.st_mode & S_IFMT == S_IFDIR,
              directoryStatus.st_uid == geteuid() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let lockURL = directory.appendingPathComponent("spotify-device-id.lock")
        let lockDescriptor = open(
            lockURL.path,
            O_CREAT | O_RDWR | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard lockDescriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { close(lockDescriptor) }
        guard flock(lockDescriptor, LOCK_EX) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { flock(lockDescriptor, LOCK_UN) }

        let fileURL = directory.appendingPathComponent(spotifyDeviceIdFileName)
        if try fileStatus(at: fileURL) != nil {
            return try readSpotifyDeviceId(from: fileURL)
        }

        if let legacyDeviceId = try legacyDeviceIdProvider() {
            return try writeSpotifyDeviceId(
                try validateSpotifyDeviceId(legacyDeviceId),
                to: fileURL
            )
        }

        var bytes = [UInt8](repeating: 0, count: 10)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else {
            throw KeychainError(operation: "generate", key: "device_id", status: randomStatus)
        }
        let id = bytes.map { String(format: "%02x", $0) }.joined()
        return try writeSpotifyDeviceId(id, to: fileURL)
    }

    private static func writeSpotifyDeviceId(_ id: String, to fileURL: URL) throws -> String {
        try Data(id.utf8).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
        return try readSpotifyDeviceId(from: fileURL)
    }

    private static func readSpotifyDeviceId(from fileURL: URL) throws -> String {
        guard let initialStatus = try fileStatus(at: fileURL),
              initialStatus.st_mode & S_IFMT == S_IFREG,
              initialStatus.st_uid == geteuid() else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let descriptor = open(fileURL.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { close(descriptor) }

        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == geteuid() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.readToEnd() ?? Data()
        guard let id = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try validateSpotifyDeviceId(id)
    }

    private static func fileStatus(at url: URL) throws -> stat? {
        var status = stat()
        if lstat(url.path, &status) == 0 {
            return status
        }
        if errno == ENOENT {
            return nil
        }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private static func validateSpotifyDeviceId(_ id: String) throws -> String {
        guard id.utf8.count == 20,
              id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return id
    }
}
