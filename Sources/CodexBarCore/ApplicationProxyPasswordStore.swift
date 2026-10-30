#if os(macOS)
import Foundation
import Security

public enum ApplicationProxyPasswordStore {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.steipete.CodexBar.application-proxy",
            kSecAttrAccount as String: "proxy-password",
        ]
    }

    public static func load() throws -> String? {
        guard !KeychainAccessGate.isDisabled else { throw StoreError.unavailable }
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        KeychainNoUIQuery.apply(to: &query)
        var result: CFTypeRef?
        let status = KeychainSecurity.copyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else { throw StoreError.unavailable }
        return password
    }

    public static func save(_ password: String) throws {
        guard !KeychainAccessGate.isDisabled else { throw StoreError.unavailable }
        var query = self.query
        KeychainNoUIQuery.apply(to: &query)
        if password.isEmpty {
            let status = KeychainSecurity.delete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.unavailable }
            return
        }
        let values: [String: Any] = [kSecValueData as String: Data(password.utf8)]
        var status = KeychainSecurity.update(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = self.query.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = KeychainSecurity.add(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StoreError.unavailable }
    }

    public enum StoreError: LocalizedError {
        case unavailable
        public var errorDescription: String? {
            "Proxy password is unavailable in Keychain. Save it again in Network & Proxy."
        }
    }
}
#endif
