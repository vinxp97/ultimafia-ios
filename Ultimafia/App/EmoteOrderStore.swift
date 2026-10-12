import Foundation

/// Per-user display order for the user's own custom emotes/stickers (autocomplete + You list).
/// Stored locally in UserDefaults and mirrored to iCloud key-value storage; newest write wins,
/// with any items only the older copy knew about appended. Not cleared on sign-out.
/// Without the iCloud entitlement/account, NSUbiquitousKeyValueStore just stays local.
final class EmoteOrderStore {
    static let shared = EmoteOrderStore()
    static let didChange = Notification.Name("um.emoteOrder.changed")

    private struct Entry: Codable {
        var order: [String]
        var updated: Double
    }

    private let kvs = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private static let prefix = "um.emoteOrder."

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs, queue: .main
        ) { note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated { EmoteOrderStore.shared.adoptCloud(keys: keys) }
        }
        kvs.synchronize()
    }

    static func key(code: String, sticker: Bool) -> String { (sticker ? "s:" : "e:") + code.lowercased() }

    func order(for userId: String?) -> [String] {
        guard let userId else { return [] }
        let key = Self.prefix + userId
        let local = decode(defaults.data(forKey: key))
        let cloud = decode(kvs.data(forKey: key))
        let merged = merge(local, cloud)
        if let merged, merged.updated != local?.updated || merged.order != local?.order {
            defaults.set(try? JSONEncoder().encode(merged), forKey: key)
        }
        return merged?.order ?? []
    }

    func rank(for userId: String?) -> [String: Int] {
        var out: [String: Int] = [:]
        for (i, k) in order(for: userId).enumerated() where out[k] == nil { out[k] = i }
        return out
    }

    func setOrder(_ order: [String], for userId: String?) {
        guard let userId else { return }
        let key = Self.prefix + userId
        let data = try? JSONEncoder().encode(Entry(order: order, updated: Date().timeIntervalSince1970))
        defaults.set(data, forKey: key)
        kvs.set(data, forKey: key)
        kvs.synchronize()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    private func adoptCloud(keys: [String]) {
        var changed = false
        for key in keys where key.hasPrefix(Self.prefix) {
            let local = decode(defaults.data(forKey: key))
            if let merged = merge(local, decode(kvs.data(forKey: key))) {
                defaults.set(try? JSONEncoder().encode(merged), forKey: key)
                changed = true
            }
        }
        if changed { NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }

    private func decode(_ data: Data?) -> Entry? {
        data.flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
    }

    private func merge(_ a: Entry?, _ b: Entry?) -> Entry? {
        guard let a else { return b }
        guard let b else { return a }
        let (win, lose) = a.updated >= b.updated ? (a, b) : (b, a)
        let known = Set(win.order)
        return Entry(order: win.order + lose.order.filter { !known.contains($0) }, updated: win.updated)
    }
}
