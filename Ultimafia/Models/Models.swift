import Foundation

struct UserInfo: Decodable, Hashable {
    var id: String?
    var name: String?
    var avatar: Bool?
    var csrf: FlexString?
    var inGame: FlexString?
    var coins: FlexInt?
    var redHearts: FlexInt?
    var goldHearts: FlexInt?
    var isDonor: Bool?
    var rank: FlexString?
    var email: String?

    var csrfToken: String? {
        let s = csrf?.value ?? ""
        return s.isEmpty ? nil : s
    }

    var inGameId: String? {
        let s = inGame?.value ?? ""
        if s.isEmpty || s == "false" || s == "0" { return nil }
        return s
    }
}

struct OnlineUser: Decodable, Hashable, Identifiable {
    var id: String
    var name: String?
    var avatar: Bool?
    var status: String?
    var vanityUrl: String?
}

enum UMText {
    static func clipped(_ s: String, limit: Int = 32) -> String {
        guard s.count > limit else { return s }
        return String(s.prefix(max(1, limit - 1))) + "…"
    }
}

struct SetupCreator: Decodable, Hashable {
    var id: String?
    var name: String?
}

struct SetupInfo: Decodable, Hashable, Identifiable {
    var id: String
    var name: String?
    var gameType: String?
    var closed: Bool?
    var total: FlexInt?
    var count: [String: Int]?
    var roles: JSONValue?
    var useRoleGroups: Bool?
    var ranked: Bool?
    var competitive: Bool?
    var featured: Bool?
    var creator: SetupCreator?

    var displayName: String {
        let raw = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Custom setup" : raw
    }

    var clippedName: String { UMText.clipped(displayName) }

    func roleBundle(defaultGameType: String = "Mafia") -> SetupRoleParse.Bundle {
        let countAny: [String: Any]? = count.map { $0.mapValues { $0 as Any } }
        return SetupRoleParse.parse(
            rolesBlob: roles?.asAny,
            closed: closed ?? false,
            useRoleGroups: useRoleGroups ?? false,
            count: countAny,
            gameType: gameType ?? defaultGameType
        )
    }

    func isSimpleMulti(defaultGameType: String = "Mafia") -> Bool {
        !(closed ?? false) && !(useRoleGroups ?? false) && roleBundle(defaultGameType: defaultGameType).rolesets.count > 1
    }
}

/// Game types the app supports in each surface. Add Liars Dice, Secret Dictator, Wacky Words,
/// Ghost here as the app learns them.
enum UMGameTypes {
    static let reviewable: Set<String> = ["Mafia"]
}

struct GameSummary: Decodable, Hashable, Identifiable {
    var id: String
    var type: String?
    var setup: SetupInfo?
    var hostId: String?
    var players: FlexInt?
    var spectatorCount: FlexInt?
    var gameState: String?
    var lobbyName: String?
    var lobby: String?
    var ranked: Bool?
    var competitive: Bool?
    var spectating: Bool?
    var `private`: Bool?
    var status: String?
    var readyCheck: Bool?
    var anonymousGame: Bool?
    var endTime: Double?

    var playerCount: Int { players?.value ?? 0 }
    var setupTotal: Int { setup?.total?.value ?? 0 }
    var isFinished: Bool { (status ?? "").caseInsensitiveCompare("Finished") == .orderedSame }
    var isOpen: Bool { (status ?? "").caseInsensitiveCompare("Open") == .orderedSame }
    var isInProgress: Bool {
        let s = (status ?? "").lowercased()
        if s == "in progress" { return true }
        if isOpen { return false }
        if s == "finished" { return false }
        return gameState != nil && gameState != "Pregame"
    }
}

struct GameConnect: Decodable {
    var port: FlexString
    var type: String?
    var token: String?
    var hostId: String?
}

struct OpenCounts: Decodable {
    var counts: [String: Int]?
    var hasOpen: Bool?

    var countValues: [String: Int] { counts ?? [:] }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasOpen = try c.decodeIfPresent(Bool.self, forKey: .hasOpen)
        if let raw = try? c.decode([String: FlexInt].self, forKey: .counts) {
            counts = raw.mapValues(\.value)
        } else {
            counts = nil
        }
    }

    enum CodingKeys: String, CodingKey { case counts, hasOpen }
}

struct FirebaseSignIn: Decodable {
    var idToken: String?
    var email: String?
    var localId: String?
    var registered: Bool?
    var error: FirebaseErrorBox?
}

struct FirebaseErrorBox: Decodable {
    var message: String?
}

enum UMError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let s): return s
        }
    }
}
