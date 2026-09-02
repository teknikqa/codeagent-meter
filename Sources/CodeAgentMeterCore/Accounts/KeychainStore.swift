import Foundation
import Security

public enum KeychainError: Error, Equatable {
    case itemNotFound
    case unexpectedData
    case osStatus(OSStatus)
}

/// Thin wrapper over the Security framework for generic-password items,
/// scoped to a single Keychain service (an app's own secrets).
public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func readData(account: String) throws -> Data {
        try Self.readData(service: service, account: account)
    }

    public func write(data: Data, account: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var newItem = baseQuery
            newItem[kSecValueData as String] = data
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.osStatus(addStatus) }
        } else {
            guard updateStatus == errSecSuccess else { throw KeychainError.osStatus(updateStatus) }
        }
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    /// Reads a generic-password item filtered by service and account.
    public static func readData(service: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return try lookup(query)
    }

    /// Reads the first generic-password item matching a service, regardless of its
    /// account attribute. Used to read Keychain items owned by other apps (e.g. the
    /// Claude Code CLI) whose exact account name isn't known to us.
    public static func readFirstData(service: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return try lookup(query)
    }

    private static func lookup(_ query: [String: Any]) throws -> Data {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw KeychainError.itemNotFound }
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
        guard let data = item as? Data else { throw KeychainError.unexpectedData }
        return data
    }
}
