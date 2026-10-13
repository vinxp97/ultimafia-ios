import Foundation

/// Anonymous deck profiles (name, avatar path, color) from `options.anonymousDeck`, kept on disk in
/// UMCache/AnonDecks so their avatar images can be prefetched into UMCustomAssetCache right away
/// on later games. Removed by Clear Cached Media with the rest of UMCache.
nonisolated enum UMDeckCache {
    static var directory: URL { UMCacheLocation.anonDecks }

    private static func file(_ id: String) -> URL {
        let safe = id.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }

    static func store(_ decks: [Any]) {
        for case let deck as [String: Any] in decks {
            guard let id = deck["id"] as? String, !id.isEmpty, JSONSerialization.isValidJSONObject(deck),
                  let data = try? JSONSerialization.data(withJSONObject: deck) else { continue }
            try? data.write(to: file(id), options: .atomic)
        }
    }

    static func profiles(deckId: String) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: file(deckId)),
              let deck = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return deck["profiles"] as? [[String: Any]] ?? []
    }

    /// Every deck profile's avatar image (web: `/uploads/decks/<profileId>.webp`).
    static func avatarURLs(deckIds: [String]) -> [URL] {
        deckIds.flatMap(profiles(deckId:)).compactMap { p -> URL? in
            if let path = UMAvatarURL.deckPath(p["avatar"]) { return UMAvatarURL.deck(path: path) }
            return nil
        }
    }
}
