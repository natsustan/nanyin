import Foundation
import Security

/// Small secrets by name. The app uses the Keychain; tests use memory.
public protocol SecretStore: Sendable {
    func read(_ name: String) throws -> Data?
    func write(_ data: Data, for name: String) throws
    func delete(_ name: String) throws
}

public extension SecretStore {
    func readValue<T: Decodable>(_ type: T.Type, _ name: String) throws -> T? {
        try read(name).map { try JSONDecoder().decode(T.self, from: $0) }
    }

    func writeValue(_ value: some Encodable, for name: String) throws {
        try write(JSONEncoder().encode(value), for: name)
    }
}

public struct KeychainError: Error, CustomStringConvertible {
    public let status: OSStatus
    public var description: String {
        "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
    }
}

/// Generic passwords under one service name.
public struct KeychainStore: SecretStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    private func query(_ name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
    }

    public func read(_ name: String) throws -> Data? {
        var query = query(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return item as? Data
    }

    public func write(_ data: Data, for name: String) throws {
        let status = SecItemUpdate(query(name) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(name)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(_ name: String) throws {
        let status = SecItemDelete(query(name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

/// For tests and previews.
public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    public init() {}

    public func read(_ name: String) throws -> Data? {
        lock.withLock { values[name] }
    }

    public func write(_ data: Data, for name: String) throws {
        lock.withLock { values[name] = data }
    }

    public func delete(_ name: String) throws {
        _ = lock.withLock { values.removeValue(forKey: name) }
    }
}
