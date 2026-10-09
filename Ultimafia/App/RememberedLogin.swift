import Foundation
import Security

enum RememberedLogin {
    private static let emailKey = "um.remember.email"
    private static let flagKey = "um.remember.enabled"
    private static let service = "VCCCLLC.Ultimafia.login"
    private static let account = "password"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: flagKey) }
        set { UserDefaults.standard.set(newValue, forKey: flagKey) }
    }

    static var email: String {
        get { UserDefaults.standard.string(forKey: emailKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: emailKey) }
    }

    static var password: String? { readPassword() }

    static func save(email: String, password: String) {
        isEnabled = true
        self.email = email
        setPassword(password)
    }

    static func clear() {
        isEnabled = false
        UserDefaults.standard.removeObject(forKey: emailKey)
        deletePassword()
    }

    private static func setPassword(_ password: String) {
        deletePassword()
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func readPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deletePassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
