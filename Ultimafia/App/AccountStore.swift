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

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.listKey),
           let list = try? JSONDecoder().decode([SavedAccount].self, from: data) {
            accounts = list
        }
    }

    var sorted: [SavedAccount] { accounts.sorted { $0.lastUsed > $1.lastUsed } }

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
        persist()
    }

    func remove(_ id: String) {
        accounts.removeAll { $0.id == id }
        clearSession(id)
        clearPassword(id)
        persist()
    }

    // MARK: Session cookies

    /// Snapshot the current ultimafia.com cookies into this account's Keychain item.
    func saveSession(for id: String) {
        let cookies = (HTTPCookieStorage.shared.cookies ?? []).filter { $0.domain.lowercased().contains("ultimafia") }
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
        UMKeychain.set(data, service: Self.sessionService, account: id)
    }

    /// Replace the cookie jar with this account's saved cookies. False if none are saved.
    func restoreSession(for id: String) -> Bool {
        Self.clearCookies()
        guard let data = UMKeychain.get(service: Self.sessionService, account: id),
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
        UMKeychain.delete(service: Self.sessionService, account: id)
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
        UserDefaults.standard.set(try? JSONEncoder().encode(accounts), forKey: Self.listKey)
    }
}
