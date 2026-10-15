import Foundation

nonisolated enum UMConfig {
    /// Selected backend host (Z-only switch on the developer profile). Persisted; .com by default.
    static var backend: UMBackend {
        UMBackend(rawValue: UserDefaults.standard.string(forKey: UMBackend.key) ?? "") ?? .com
    }
    static var host: String { backend.rawValue }
    /// "https://<host>" with no trailing slash.
    static var site: String { "https://\(host)" }
    static var apiBase: URL { URL(string: "\(site)/api")! }
    static var siteBase: URL { URL(string: site)! }
    static var socketBase: URL { URL(string: "wss://\(host)")! }

    /// Cookie domain belongs to the selected host (".ultimafia.gg" also covers dev./qa.).
    static func cookieMatchesHost(_ domain: String) -> Bool {
        var d = domain.lowercased()
        if d.hasPrefix(".") { d.removeFirst() }
        return host == d || host.hasSuffix("." + d)
    }
    /// Public web API key from the ultimafia.com client.
    /// Defined in Ultimafia/App/Secrets.swift.
    static let firebaseAPIKey = UMSecrets.firebaseAPIKey
    static let allowedEmailDomains: Set<String> = [
        "gmail.com", "hotmail.com", "aol.com", "msn.com", "yandex.ru",
        "live.com", "icloud.com", "gmail.com.sg", "yahoo.com", "mail.com",
        "outlook.com", "hotmail.co.uk",
    ]
    static let lobbies = ["Main", "Sandbox", "Competitive", "Games", "Survivor", "Roleplay"]
    static let maxChatLength = 240
    static let pingInterval: TimeInterval = 10
}

nonisolated enum UMBackend: String, CaseIterable, Identifiable {
    case com = "ultimafia.com"
    case gg = "ultimafia.gg"
    case dev = "dev.ultimafia.gg"
    case qa = "qa.ultimafia.gg"
    static let key = "um.backend.host"
    var id: String { rawValue }
    static func set(_ b: UMBackend) { UserDefaults.standard.set(b.rawValue, forKey: key) }
}
