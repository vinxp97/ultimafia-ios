import Foundation

/// Z's profile (the You-page credits link) cached ahead of time so it opens instantly.
/// Stored in UMCache/UMProfiles (Application Support; survives sign-out, not purged by iOS).
/// GET only. Refetched when missing or older than 7 days; "Clear cached media" deletes the
/// folder, so the next launch re-prefetches. Never touches logins.
nonisolated enum UMDevProfileCache {
    static let userId = "Fy2Ee8BH9"
    static let maxAge: TimeInterval = 7 * 24 * 3600
    /// Total media cap for one prefetch pass; videos are never fetched.
    static let maxMediaBytes = 30 << 20

    static var directory: URL { UMCacheLocation.dir("UMProfiles") }
    private static var jsonFile: URL { directory.appendingPathComponent("\(userId).json") }
    private static var metaFile: URL { directory.appendingPathComponent("\(userId).fetched") }

    static func isCached(_ id: String) -> Bool { id == userId }

    /// Cached profile JSON, if any (any age; the view revalidates).
    static func cachedProfile() -> [String: Any]? {
        guard let data = try? Data(contentsOf: jsonFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    static var fetchedAt: Date? {
        guard let s = try? String(contentsOf: metaFile, encoding: .utf8), let t = Double(s) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    static var needsRefresh: Bool {
        guard FileManager.default.fileExists(atPath: jsonFile.path), let t = fetchedAt else { return true }
        return Date().timeIntervalSince(t) > maxAge
    }

    static func store(_ data: Data) {
        try? data.write(to: jsonFile, options: .atomic)
        try? String(Date().timeIntervalSince1970).write(to: metaFile, atomically: true, encoding: .utf8)
    }

    /// Low-priority background prefetch of the JSON and every asset the profile page shows.
    static func prefetchIfNeeded() async {
        guard needsRefresh else { return }
        guard let data = try? await APIClient.shared.request("GET", path: "user/\(userId)/profile", query: [:], body: nil),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        store(data)
        var budget = maxMediaBytes
        for url in assetURLs(obj) {
            guard budget > 0 else { break }
            if let bytes = try? await UMImageCache.shared.data(for: url) { budget -= bytes.count }
        }
    }

    /// Same URLs UserProfileView builds (uploads go to UMCustomAssetCache, others to the UMImages URLCache).
    static func assetURLs(_ p: [String: Any]) -> [URL] {
        func b(_ any: Any?) -> Bool { (any as? Bool) ?? ((any as? NSNumber)?.boolValue ?? false) }
        let id = (p["id"] as? String) ?? userId
        let up = "https://ultimafia.com/uploads/"
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
            else if s.hasPrefix("/") { abs = "https://ultimafia.com" + s }
            else { abs = "https://ultimafia.com/" + s }
            guard let u = URL(string: abs), !videoExts.contains(u.pathExtension.lowercased()),
                  seen.insert(u.absoluteString).inserted else { return nil }
            return u
        }
    }
}
