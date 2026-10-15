import Foundation

/// Setup search + hosting, per routes/setup.js `GET /setup/search` and routes/game.js `POST /game/host`.
enum SetupFilter: String, CaseIterable, Identifiable {
    case popular = "Popular", featured = "Featured", yours = "Yours"
    case ranked = "Ranked", competitive = "Competitive", all = "All"
    var id: String { rawValue }
    /// `option` query value; All sends none.
    var option: String? { self == .all ? nil : rawValue.lowercased() }
}

struct SetupSearchPage: Decodable {
    var setups: [SetupInfo]
    var pages: Int
}

/// Mafia host options. Defaults mirror the web's HostMafia / DefaultValues.js.
struct HostOptions: Equatable {
    var gameType = "Mafia"
    // Liars Dice (web HostLiarsDice / DefaultValues.js).
    var wildOnes = true
    var spotOn = true
    var startingDice = 5        // 1...20
    var guessDiceLength = 2.0   // minutes, 0.5...5
    var isLiarsDice: Bool { gameType == "Liars Dice" }
    var lobby = "Main"
    var lobbyName = ""
    var isPrivate = false
    var guests = false
    var spectating = true
    var readyCheck = true
    var anonymousGame = false
    var anonymousDeckId = "jWqL8KjS_"   // web PreferredDeckId
    var ranked = false
    var competitive = false
    var advancedHosting = false
    var noVeg = false
    var configureDuration = false
    var dayLength = 10          // minutes, 1...30
    var nightLength = 2         // minutes, 1...10
    var pregameWaitLength = 1   // hours, 1...6
    var extendLength = 3        // minutes, 0...5

    static let lobbies = ["Main", "Sandbox", "Competitive", "Games", "Survivor", "Roleplay"]

    // Visibility rules (web `showIf`).
    var showPrivateAndGuests: Bool { !ranked && !competitive }
    var showRanked: Bool { !isLiarsDice && !isPrivate && !guests && !competitive && !advancedHosting }
    var showCompetitive: Bool { !isLiarsDice && !isPrivate && !guests && !ranked && !advancedHosting }
    var showAdvanced: Bool { !isLiarsDice && !ranked && !competitive }
    var showNoVeg: Bool { !isLiarsDice && !ranked && !competitive }
    var showDuration: Bool { !competitive }

    /// Hidden fields still hold values on web; only send what's visible so we never trip server checks.
    func body(setupId: String) -> [String: Any] {
        let dur = configureDuration && showDuration
        if isLiarsDice {
            // Same fields the web's HostLiarsDice posts.
            return [
                "gameType": gameType,
                "setup": setupId,
                "lobby": lobby,
                "lobbyName": lobbyName.trimmingCharacters(in: .whitespacesAndNewlines),
                "private": isPrivate,
                "guests": guests,
                "spectating": spectating,
                "readyCheck": readyCheck,
                "stateLengths": ["Guess Dice": configureDuration ? guessDiceLength : 1],
                "wildOnes": wildOnes,
                "spotOn": spotOn,
                "startingDice": startingDice,
                "anonymousGame": anonymousGame,
                "anonymousDeckId": anonymousDeckId,
            ]
        }
        return [
            "gameType": "Mafia",
            "lobby": lobby,
            "setup": setupId,
            "lobbyName": lobbyName.trimmingCharacters(in: .whitespacesAndNewlines),
            "private": showPrivateAndGuests && isPrivate,
            "guests": showPrivateAndGuests && guests,
            "ranked": showRanked && ranked,
            "competitive": showCompetitive && competitive,
            "spectating": spectating,
            "readyCheck": readyCheck,
            "noVeg": showNoVeg && noVeg,
            // Server falls back to its defaults for out-of-range / missing values.
            "stateLengths": ["Day": dur ? dayLength : 10, "Night": dur ? nightLength : 2],
            "pregameWaitLength": dur ? pregameWaitLength : 1,
            "extendLength": dur ? extendLength : 3,
            "anonymousGame": anonymousGame,
            "anonymousDeckId": anonymousDeckId,
            "advancedHosting": showAdvanced && advancedHosting,
        ]
    }
}

extension APIClient {
    func searchSetups(filter: SetupFilter, query: String, page: Int, gameType: String = "Mafia") async throws -> SetupSearchPage {
        var q: [String: String] = ["gameType": gameType, "page": String(page)]
        if let o = filter.option { q["option"] = o }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { q["query"] = trimmed }
        return try await get("setup/search", query: q)
    }

    /// Returns the new game id (server sends it as plain text).
    func hostGame(_ options: HostOptions, setupId: String) async throws -> String {
        let data = try await post("game/host", json: options.body(setupId: setupId))
        let id = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t"))
        guard !id.isEmpty, !id.contains("<") else { throw UMError.message("Host failed: unexpected response.") }
        return id
    }
}
