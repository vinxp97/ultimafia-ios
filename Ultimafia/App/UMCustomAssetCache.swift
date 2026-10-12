import Foundation
import CryptoKit

/// On-disk store for custom *user* assets only (custom emotes, stickers, avatars under
/// ultimafia.com/uploads). Lives in Caches/UMCustomAssets so it can be cleared without touching
/// bundled role icons, fonts, sounds or site emotes.
///
/// Device-wide by design: keyed only by asset URL, never by account, so every saved account
/// shares it and an account switch never re-downloads. Sign-out / switching must not clear it.
/// `clear()` touches only this folder: Keychain sessions/passwords, the account list, the
/// install ID and emote order/settings (UserDefaults / iCloud KVS) are never affected.
actor UMCustomAssetCache {
    static let shared = UMCustomAssetCache()

    nonisolated static let directory: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("UMCustomAssets", isDirectory: true)

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    private var inflight: [URL: Task<Data, Error>] = [:]
    private var refreshedAvatars: Set<URL> = []

    /// User uploads (avatars, custom emotes/stickers) on the site's own host.
    nonisolated static func isCustomUserAsset(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), host == "ultimafia.com" || host.hasSuffix(".ultimafia.com") else { return false }
        return url.path.hasPrefix("/uploads/")
    }

    nonisolated private static func isAvatar(_ url: URL) -> Bool { url.lastPathComponent.contains("_avatar") }

    nonisolated private static func file(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest)
    }

    func data(for url: URL) async throws -> Data {
        let file = Self.file(for: url)
        if let cached = try? Data(contentsOf: file), !cached.isEmpty {
            // Avatars can change; refresh each once per launch in the background.
            if Self.isAvatar(url), !refreshedAvatars.contains(url) {
                refreshedAvatars.insert(url)
                Task { _ = try? await self.fetch(url) }
            }
            return cached
        }
        if Self.isAvatar(url) { refreshedAvatars.insert(url) }
        return try await fetch(url)
    }

    private func fetch(_ url: URL) async throws -> Data {
        if let running = inflight[url] { return try await running.value }
        let session = self.session
        let task = Task<Data, Error> {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 { throw URLError(.badServerResponse) }
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? data.write(to: Self.file(for: url), options: .atomic)
            return data
        }
        inflight[url] = task
        defer { inflight[url] = nil }
        return try await task.value
    }

    /// Warm the disk cache; already-cached files are skipped.
    func prefetch(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            var started = 0
            for url in Set(urls) where Self.isCustomUserAsset(url) {
                if FileManager.default.fileExists(atPath: Self.file(for: url).path) { continue }
                if started >= 6 { await group.next(); started -= 1 }
                group.addTask { _ = try? await self.fetch(url) }
                started += 1
            }
        }
    }

    nonisolated static func diskBytes() -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return 0 }
        return items.reduce(0) { sum, item in
            let v = try? item.resourceValues(forKeys: keys)
            return sum + Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
    }

    /// Deletes only the custom-asset folder. Returns bytes freed.
    @discardableResult
    func clear() -> Int64 {
        let bytes = Self.diskBytes()
        try? FileManager.default.removeItem(at: Self.directory)
        refreshedAvatars.removeAll()
        return bytes
    }
}
