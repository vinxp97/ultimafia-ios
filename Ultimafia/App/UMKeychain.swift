import Foundation
import Security

/// Small generic-password wrapper.
/// Default items sync through iCloud Keychain (kSecAttrSynchronizable, AfterFirstUnlock) so saved
/// sessions/passwords/account list follow the user to their other devices. Pass `synced: false`
/// for device-only data (install ID): those use ThisDeviceOnly and never sync.
/// Reads/deletes match kSecAttrSynchronizableAny so legacy device-only items are still found.
/// No keychain-access-groups entitlement is needed: items live in the app's default group.
nonisolated enum UMKeychain {
    static func set(_ data: Data, service: String, account: String, synced: Bool = true) {
        if skipped { return }
        delete(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synced ? kCFBooleanTrue! : kCFBooleanFalse!,
            kSecAttrAccessible as String: synced
                ? kSecAttrAccessibleAfterFirstUnlock
                : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: data,
        ]
        SecItemAdd(adapt(query) as CFDictionary, nil)
    }

    static func get(service: String, account: String) -> Data? {
        if skipped { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(adapt(query) as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(service: String, account: String) {
        if skipped { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(adapt(query) as CFDictionary)
    }

    /// Account names of every item under `service` (synced or not).
    static func accounts(service: String) -> [String] {
        if skipped { return [] }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(adapt(query) as CFDictionary, &out) == errSecSuccess,
              let items = out as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    /// Mac (Catalyst) builds signed to run locally have no application-identifier entitlement, so
    /// the data-protection keychain and iCloud Keychain sync are unavailable (errSecMissingEntitlement).
    /// Those builds fall back to the login keychain, device-only. Team-signed builds keep the
    /// default behaviour; iPhone/iPad are unchanged.
    /// DEBUG `-UMNoKeychain`: screenshot/diag runs never touch the keychain (no access prompts).
    #if DEBUG
    static let skipped = ProcessInfo.processInfo.arguments.contains("-UMNoKeychain")
    #else
    static let skipped = false
    #endif

    private static func adapt(_ query: [String: Any]) -> [String: Any] {
        #if targetEnvironment(macCatalyst) || os(macOS)
        guard !hasAppIdentifier else { return query }
        var q = query
        q.removeValue(forKey: kSecUseDataProtectionKeychain as String)
        q.removeValue(forKey: kSecAttrSynchronizable as String)
        q.removeValue(forKey: kSecAttrAccessible as String)
        return q
        #else
        return query
        #endif
    }

    #if targetEnvironment(macCatalyst) || os(macOS)
    /// True when the binary carries a team prefix (embedded provisioning profile present).
    private static let hasAppIdentifier: Bool =
        Bundle.main.url(forResource: "embedded", withExtension: "provisionprofile") != nil
            || FileManager.default.fileExists(atPath: Bundle.main.bundleURL
                .appendingPathComponent("Contents/embedded.provisionprofile").path)
    #endif
}
