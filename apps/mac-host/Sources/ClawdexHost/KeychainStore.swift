import Foundation
import Security

enum KeychainStore {
    static func loadToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: HostDefaults.keychainService,
            kSecAttrAccount as String: HostDefaults.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
                throw HostError.keychain("Bridge token is unreadable in Keychain.")
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw HostError.keychain("Failed to read bridge token from Keychain (\(status)).")
        }
    }

    static func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: HostDefaults.keychainService,
            kSecAttrAccount as String: HostDefaults.keychainAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = baseQuery
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw HostError.keychain("Failed to save bridge token to Keychain (\(addStatus)).")
            }
        default:
            throw HostError.keychain("Failed to update bridge token in Keychain (\(status)).")
        }
    }
}

