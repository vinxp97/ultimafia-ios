import Foundation
import Observation

/// Non-secret profile info for an account saved on this device (UserDefaults JSON).
struct SavedAccount: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var email: String?
    var hasAvatar: Bool
    var squareAvatar: Bool
    var nameColorHex: String?
    var nameFont: String?
    var animatedNameColor: String?
    var gradientA: String?
    var gradientB: String?
    var gradientC: String?
    var lastUsed: Date

    var player: GamePlayer {
        var p = GamePlayer(
            id: id, name: name, userId: id, avatar: hasAvatar,
            nameColorHex: nameColorHex, nameFont: nameFont, animatedNameColor: animatedNameColor,
            nameGradientColorA: gradientA, nameGradientColorB: gradientB, nameGradientColorC: gradientC
        )
        p.squareAvatar = squareAvatar
        return p
    }
}

/// Saved accounts for the sign-in switcher. Session cookies and passwords live in the Keychain,
/// one item per account; only display info is in UserDefaults.
@Observable
final class AccountStore {
    static let shared = AccountStore()
    private(set) var accounts: [SavedAccount] = []

    private static let listKey = "um.accounts"
    private static let sessionService = "VCCCLLC.Ultimafia.session"
    private static let passwordService = "VCCCLLC.Ultimafia.password"

    /// Account list (display info only) lives in a synced Keychain item so it follows the user
    /// via iCloud Keychain; UserDefaults keeps a local mirror.
    private static let listService = "VCCCLLC.Ultimafia.accounts"
    private static let migratedKey = "um.accounts.keychainSync.v1"
    private static let orderKey = "um.accounts.order"

    /// User-chosen display order (account ids), mirrored to iCloud KVS like the emote order.
    private(set) var order: [String] = []
    private let kvs = NSUbiquitousKeyValueStore.default

    private struct OrderEntry: Codable { var order: [String]; var updated: Double }

    private init() {
        let fromKeychain = UMKeychain.get(service: Self.listService, account: "list")
            .flatMap { try? JSONDecoder().decode([SavedAccount].self, from: $0) }
        let fromDefaults = UserDefaults.standard.data(forKey: Self.listKey)
            .flatMap { try? JSONDecoder().decode([SavedAccount].self, from: $0) }
        var merged = fromKeychain ?? []
        for a in fromDefaults ?? [] where !merged.contains(where: { $0.id == a.id }) { merged.append(a) }
        accounts = merged
        UMProfileCache.setSavedAccounts(accounts.map(\.id))
        order = Self.loadOrder(kvs: kvs)
        migrateKeychainOnce()
        persist()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs, queue: .main
        ) { note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard keys.contains(AccountStore.orderKey) else { return }
            MainActor.assumeIsolated { AccountStore.shared.reloadOrder() }
        }
    }

    /// One-time: re-store legacy device-only session/password items as iCloud-synced ones.
    private func migrateKeychainOnce() {
        guard !UserDefaults.standard.bool(forKey: Self.migratedKey) else { return }
        for service in [Self.sessionService, Self.passwordService] {
            for id in UMKeychain.accounts(service: service) {
                if let data = UMKeychain.get(service: service, account: id) {
                    UMKeychain.set(data, service: service, account: id)
                }
            }
        }
        UserDefaults.standard.set(true, forKey: Self.migratedKey)
    }

    private static func loadOrder(kvs: NSUbiquitousKeyValueStore) -> [String] {
        func decode(_ d: Data?) -> OrderEntry? { d.flatMap { try? JSONDecoder().decode(OrderEntry.self, from: $0) } }
        let local = decode(UserDefaults.standard.data(forKey: orderKey))
        let cloud = decode(kvs.data(forKey: orderKey))
        switch (local, cloud) {
        case let (l?, c?): return c.updated > l.updated ? c.order : l.order
        case let (l?, nil): return l.order
        case let (nil, c?): return c.order
        default: return []
        }
    }

    func reloadOrder() { order = Self.loadOrder(kvs: kvs) }

    /// Saved accounts in the user's order; accounts not yet ordered follow, most recent first.
    var sorted: [SavedAccount] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return accounts.sorted { a, b in
            switch (rank[a.id], rank[b.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.lastUsed > b.lastUsed
            }
        }
    }

    func setOrder(_ ids: [String]) {
        order = ids
        let data = try? JSONEncoder().encode(OrderEntry(order: ids, updated: Date().timeIntervalSince1970))
        UserDefaults.standard.set(data, forKey: Self.orderKey)
        kvs.set(data, forKey: Self.orderKey)
        kvs.synchronize()
    }

    func upsert(_ info: UserInfo, email: String?) {
        guard let id = info.id else { return }
        let p = info.cosmeticPlayer
        let previous = accounts.first { $0.id == id }
        let row = SavedAccount(
            id: id, name: info.name ?? previous?.name ?? "Unknown",
            email: email ?? info.email ?? previous?.email,
            hasAvatar: p.avatar, squareAvatar: p.squareAvatar,
            nameColorHex: p.nameColorHex, nameFont: p.nameFont, animatedNameColor: p.animatedNameColor,
            gradientA: p.nameGradientColorA, gradientB: p.nameGradientColorB, gradientC: p.nameGradientColorC,
            lastUsed: Date()
        )
        accounts.removeAll { $0.id == id }
        accounts.append(row)
        UMProfileCache.setSavedAccounts(accounts.map(\.id))
        persist()
    }

    func remove(_ id: String) {
        accounts.removeAll { $0.id == id }
        UMProfileCache.remove(id)
        UMProfileCache.setSavedAccounts(accounts.map(\.id))
        if order.contains(id) { setOrder(order.filter { $0 != id }) }
        clearSession(id)
        clearPassword(id)
        persist()
    }

    // MARK: Session cookies

    /// Snapshot the current ultimafia.com cookies into this account's Keychain item.
    func saveSession(for id: String) {
        let cookies = (HTTPCookieStorage.shared.cookies ?? []).filter { UMConfig.cookieMatchesHost($0.domain) }
        guard !cookies.isEmpty else { return }
        let list: [[String: Any]] = cookies.compactMap { cookie in
            guard let props = cookie.properties else { return nil }
            var out: [String: Any] = [:]
            for (k, v) in props {
                switch v {
                case let url as URL: out[k.rawValue] = url.absoluteString
                case is String, is Date, is NSNumber: out[k.rawValue] = v
                default: break
                }
            }
            return out
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: list, format: .binary, options: 0) else { return }
        UMKeychain.set(data, service: Self.sessionService, account: Self.sessionKey(id))
    }

    /// Replace the cookie jar with this account's saved cookies. False if none are saved.
    func restoreSession(for id: String) -> Bool {
        Self.clearCookies()
        guard let data = UMKeychain.get(service: Self.sessionService, account: Self.sessionKey(id)),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { return false }
        var restored = 0
        for props in list {
            var typed: [HTTPCookiePropertyKey: Any] = [:]
            for (k, v) in props { typed[HTTPCookiePropertyKey(k)] = v }
            if let cookie = HTTPCookie(properties: typed) {
                HTTPCookieStorage.shared.setCookie(cookie)
                restored += 1
            }
        }
        return restored > 0
    }

    func clearSession(_ id: String) {
        UMKeychain.delete(service: Self.sessionService, account: Self.sessionKey(id))
    }

    /// Sessions are per backend host (cookies are per domain): .com keeps the bare id (existing items).
    static func sessionKey(_ id: String) -> String {
        UMConfig.backend == .com ? id : "\(id)@\(UMConfig.host)"
    }

    static func clearCookies() {
        for cookie in HTTPCookieStorage.shared.cookies ?? [] {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    // MARK: Passwords

    func savePassword(_ password: String, for id: String) {
        UMKeychain.set(Data(password.utf8), service: Self.passwordService, account: id)
    }

    func password(for id: String) -> String? {
        UMKeychain.get(service: Self.passwordService, account: id).flatMap { String(data: $0, encoding: .utf8) }
    }

    func clearPassword(_ id: String) {
        UMKeychain.delete(service: Self.passwordService, account: id)
    }

    private func persist() {
        let data = try? JSONEncoder().encode(accounts)
        UserDefaults.standard.set(data, forKey: Self.listKey)
        if let data { UMKeychain.set(data, service: Self.listService, account: "list") }
    }
}
