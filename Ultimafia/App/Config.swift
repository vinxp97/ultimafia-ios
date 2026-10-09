import Foundation

enum UMConfig {
    static let apiBase = URL(string: "https://ultimafia.com/api")!
    static let siteBase = URL(string: "https://ultimafia.com")!
    static let socketBase = URL(string: "wss://ultimafia.com")!
    /// Public web API key from the ultimafia.com client.
    /// Kept out of git: defined in Ultimafia/App/Secrets.swift (gitignored).
    /// See Secrets.swift.template at the repo root.
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
