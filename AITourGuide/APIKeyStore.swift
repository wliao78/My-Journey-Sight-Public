import Foundation
import Security

struct APIKeyStore {
    private let service: String
    private let account = "user-api-key"

    init(provider: PublicAIProvider = .selected) {
        service = "com.myjourney.public.sight.\(provider.rawValue)"
    }

    func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ key: String) -> Bool {
        guard let data = key.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8), !data.isEmpty else { return false }
        let selector: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if SecItemUpdate(selector as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess { return true }
        return SecItemAdd((selector.merging([
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]) { _, new in new }) as CFDictionary, nil) == errSecSuccess
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
