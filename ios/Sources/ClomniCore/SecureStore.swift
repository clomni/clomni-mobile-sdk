import Foundation
#if canImport(Security)
import Security
#endif

/// Small secrets: the session and refresh tokens, the identity to log in again with, the anonymous user and the device id.
protocol SecureStore: Sendable {
    func read(_ key: String) -> Data?
    /// nil deletes.
    func write(_ data: Data?, for key: String)
}

extension SecureStore {
    func value<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        read(key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func setValue<T: Encodable>(_ value: T?, for key: String) {
        write(value.flatMap { try? JSONEncoder().encode($0) }, for: key)
    }
}

/// For tests, and wherever there is no Keychain.
final class MemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    func read(_ key: String) -> Data? {
        IOProbe.note("vault read \(key)")
        lock.lock()
        defer { lock.unlock() }
        return items[key]
    }

    func write(_ data: Data?, for key: String) {
        IOProbe.note("vault write \(key)")
        lock.lock()
        defer { lock.unlock() }
        items[key] = data
    }
}

#if canImport(Security)
/// Keychain items of one app id, readable after the first unlock and never restored to another device.
final class KeychainStore: SecureStore, @unchecked Sendable {
    private let service: String

    init(appId: String) {
        service = "ai.clomni.messenger.\(appId)"
    }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    func read(_ key: String) -> Data? {
        IOProbe.note("vault read \(key)")
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func write(_ data: Data?, for key: String) {
        IOProbe.note("vault write \(key)")
        SecItemDelete(query(key) as CFDictionary)
        guard let data else { return }
        var item = query(key)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
#endif
