import Foundation

/// Profiles cached ahead of time so they open instantly (stale-while-revalidate).
/// Stored in UMCache/UMProfiles (Application Support; survives sign-out, not purged by iOS).
/// GET only. Two policies:
/// - Z (the You-page credits link): refetched when missing or older than 7 days.
/// - Saved accounts (every account in the switcher): no expiry; kept current by the quiet refresh
///   whenever the profile is opened, and after your own uploads/removals in Advanced Settings.
/// "Clear cached media" deletes the folder; the next launch re-prefetches. Never touches logins.
nonisolated enum UMProfileCache {
    static let devUserId = "Fy2Ee8BH9"
    static let devMaxAge: TimeInterval = 7 * 24 * 3600
    /// Media cap per profile per pass; videos are never fetched.
    static let maxMediaBytes = 30 << 20

    /// Active session user (set from AppModel.user).
    static let activeUserId = UMLocked<String?>(nil)
    /// Ids that get cached: Z plus every saved account (set from the account list).
    private static let savedIds = UMLocked<Set<String>>([])

    static var directory: URL { UMCacheLocation.dir("UMProfiles") }
    private static func jsonFile(_ id: String) -> URL { directory.appendingPathComponent("\(safe(id)).json") }
    private static func metaFile(_ id: String) -> URL { directory.appendingPathComponent("\(safe(id)).fetched") }
    private static func safe(_ id: String) -> String { id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }

    /// Backend switch: profiles are per host.
    static func clearAll() { try? FileManager.default.removeItem(at: directory) }

    static func setSavedAccounts(_ ids: [String]) { savedIds.withLock { $0 = Set(ids) } }

    static func isCached(_ id: String) -> Bool {
        id == devUserId || savedIds.withLock { $0.contains(id) }
    }

    static func cachedProfile(_ id: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: jsonFile(id)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    static func fetchedAt(_ id: String) -> Date? {
        guard let s = try? String(contentsOf: metaFile(id), encoding: .utf8), let t = Double(s) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    /// Z expires after 7 days; accounts only when missing.
    static func needsRefresh(_ id: String) -> Bool {
        guard FileManager.default.fileExists(atPath: jsonFile(id).path) else { return true }
        guard id == devUserId else { return false }
        guard let t = fetchedAt(id) else { return true }
        return Date().timeIntervalSince(t) > devMaxAge
    }

    static func store(_ data: Data, for id: String) {
        try? data.write(to: jsonFile(id), options: .atomic)
        try? String(Date().timeIntervalSince1970).write(to: metaFile(id), atomically: true, encoding: .utf8)
    }

    static func remove(_ id: String) {
        guard id != devUserId else { return }
        try? FileManager.default.removeItem(at: jsonFile(id))
        try? FileManager.default.removeItem(at: metaFile(id))
    }

    /// Background pass after launch: Z (if stale) and every saved account (if missing).
    static func prefetchAll(accountIds: [String]) async {
        setSavedAccounts(accountIds)
        for id in [devUserId] + accountIds where needsRefresh(id) {
            await fetch(id, withMedia: true)
        }
    }

    /// GET the profile JSON, store it, then warm its assets (capped, no video).
    @discardableResult
    static func fetch(_ id: String, withMedia: Bool) async -> [String: Any]? {
        guard let data = try? await APIClient.shared.request("GET", path: "user/\(id)/profile", query: [:], body: nil),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        store(data, for: id)
        if withMedia {
            var budget = maxMediaBytes
            for url in assetURLs(obj, fallbackId: id) {
                guard budget > 0 else { break }
                if let bytes = try? await UMImageCache.shared.data(for: url) { budget -= bytes.count }
            }
        }
        return obj
    }

    /// After your own successful upload/removal/settings change: refresh your cached profile.
    static func refreshActiveAccount() async {
        guard let id = activeUserId.withLock({ $0 }), isCached(id) else { return }
        await fetch(id, withMedia: true)
    }

    /// Same URLs UserProfileView builds (uploads go to UMCustomAssetCache, others to the UMImages URLCache).
    static func assetURLs(_ p: [String: Any], fallbackId: String) -> [URL] {
        func b(_ any: Any?) -> Bool { (any as? Bool) ?? ((any as? NSNumber)?.boolValue ?? false) }
        let id = (p["id"] as? String) ?? fallbackId
        let up = "\(UMConfig.site)/uploads/"
        var out: [String] = []
        if b(p["avatar"]) { out.append("\(up)\(id)_avatar.webp") }
        if b(p["banner"]) {
            let ext = ((p["bannerExt"] as? String) ?? "webp").filter { $0.isLetter || $0.isNumber }
            out.append("\(up)\(id)_banner.\(ext.isEmpty ? "webp" : ext)")
        }
        if b(p["profileBackground"]) { out.append("\(up)\(id)_profileBackground.webp") }
        if let fam = p["family"] as? [String: Any], b(fam["avatar"]), let fid = fam["id"] as? String {
            out.append("\(up)\(fid)_family_avatar.webp")
        }
        for key in ["love", "currentLove"] {
            if let l = p[key] as? [String: Any], b(l["avatar"]), let lid = l["id"] as? String {
                out.append("\(up)\(lid)_avatar.webp")
            }
        }
        if let t = p["trophies"] as? [[String: Any]] {
            for tr in t {
                if let o = tr["owner"] as? [String: Any], b(o["avatar"]), let oid = o["id"] as? String {
                    out.append("\(up)\(oid)_avatar.webp")
                }
            }
        }
        // Images/GIFs in the bio (markdown and <img>), resolved like UMMarkdownView.
        let bio = (p["bio"] as? String) ?? ""
        for pattern in [#"!\[[^\]]*\]\(\s*<?([^)\s>]+)"#, #"<img[^>]*?src\s*=\s*["']([^"']+)["']"#] {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for m in re.matches(in: bio, range: NSRange(bio.startIndex..., in: bio)) {
                if let r = Range(m.range(at: 1), in: bio) { out.append(String(bio[r])) }
            }
        }
        let videoExts: Set<String> = ["mp4", "webm", "mov", "m4v", "avi", "mkv"]
        var seen = Set<String>()
        return out.compactMap { s -> URL? in
            let abs: String
            if s.hasPrefix("http://") || s.hasPrefix("https://") { abs = s }
            else if s.hasPrefix("//") { abs = "https:" + s }
            else if s.hasPrefix("/") { abs = "\(UMConfig.site)" + s }
            else { abs = "\(UMConfig.site)/" + s }
            guard let u = URL(string: abs), !videoExts.contains(u.pathExtension.lowercased()),
                  seen.insert(u.absoluteString).inserted else { return nil }
            return u
        }
    }
}
