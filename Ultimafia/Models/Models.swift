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
    var settings: JSONValue?
    var itemsOwned: JSONValue?
    /// GET user/info `perms` (permission name -> true), used to gate settings like the site.
    var perms: JSONValue?
    /// GET user/info `blockedUsers` (user ids); toggled by POST user/block.
    var blockedUsers: [String]?

    /// The user's own cosmetics as a GamePlayer, so the You tab reuses chat's name/avatar styling.
    var cosmeticPlayer: GamePlayer {
        let st = settings?.asAny as? [String: Any] ?? [:]
        let items = itemsOwned?.asAny as? [String: Any] ?? [:]
        // Same rule as server User.js: square only if the Square item is owned.
        let ownsSquare = (items["avatarShape"] as? Double ?? 0) > 0 || (items["avatarShape"] as? Bool ?? false)
        var p = GamePlayer(
            id: id ?? "me",
            name: name ?? "Unknown",
            userId: id,
            avatar: avatar ?? false,
            nameColorHex: umColorString(st["nameColor"]),
            nameFont: st["nameFont"] as? String,
            animatedNameColor: st["animatedNameColor"] as? String,
            nameGradientColorA: umColorString(st["nameGradientColorA"]),
            nameGradientColorB: umColorString(st["nameGradientColorB"]),
            nameGradientColorC: umColorString(st["nameGradientColorC"])
        )
        p.squareAvatar = ownsSquare && (st["gameAvatarShape"] as? String) == "square"
        return p
    }

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
    var roleGroupSizes: [FlexInt]?
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
            gameType: gameType ?? defaultGameType,
            roleGroupSizes: (roleGroupSizes ?? []).map(\.value)
        )
    }

    func isSimpleMulti(defaultGameType: String = "Mafia") -> Bool {
        !(closed ?? false) && !(useRoleGroups ?? false) && roleBundle(defaultGameType: defaultGameType).rolesets.count > 1
    }
}

/// Game types the app supports in each surface. Add Liars Dice, Secret Dictator, Wacky Words,
/// Ghost here as the app learns them.
enum UMGameTypes {
    static let reviewable: Set<String> = ["Mafia", "Liars Dice"]
    static let hostable = ["Mafia", "Liars Dice"]
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
    var broken: Bool?
    /// Finished games only: JSON string of seat id -> user id.
    var playerIdMap: String?

    /// Mirrors the server's review/data gate (`!private || reviewPrivate perm || user played`)
    /// and the web GameRow, which hides the review button for private or broken games.
    /// The reviewPrivate permission isn't exposed to the client, so mods see the same filter.
    func isReviewVisible(to userId: String?) -> Bool {
        if broken == true { return false }
        guard `private` == true else { return true }
        guard let userId, let data = playerIdMap?.data(using: .utf8),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return map.values.contains { ($0 as? String) == userId }
    }

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

/// Definite auth rejection: HTTP 401/403, Firebase invalid credentials, or /user/info not logged in.
/// Distinct from network failures so saved accounts are only dropped when the server said no.
struct UMAuthRejected: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

enum UMError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let s): return s
        }
    }
}
