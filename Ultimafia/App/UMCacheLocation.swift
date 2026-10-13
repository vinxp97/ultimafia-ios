import Foundation

/// One device-wide cache folder shared by every account: Application Support/UMCache.
/// Unlike Caches/, iOS doesn't purge it under storage pressure; only the You-tab clear button
/// empties it. Excluded from iCloud/device backups. Never holds logins, settings or order data.
nonisolated enum UMCacheLocation {
    static let root: URL = {
        let fm = FileManager.default
        var url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UMCache", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        migrateFromCachesOnce(into: url)
        return url
    }()

    static func dir(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var customAssets: URL { dir("UMCustomAssets") }
    static var images: URL { root.appendingPathComponent("UMImages", isDirectory: true) }
    static var nameFonts: URL { dir("UMNameFonts") }
    static var sounds: URL { dir("Sounds") }
    static var anonDecks: URL { dir("AnonDecks") }

    /// Move the old Caches/ folders and sound files here once, then remove the leftovers.
    private static func migrateFromCachesOnce(into root: URL) {
        let key = "um.cache.movedToAppSupport.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        for name in ["UMCustomAssets", "UMNameFonts", "UMImages"] {
            let old = caches.appendingPathComponent(name, isDirectory: true)
            let new = root.appendingPathComponent(name, isDirectory: true)
            guard fm.fileExists(atPath: old.path) else { continue }
            if !fm.fileExists(atPath: new.path), (try? fm.moveItem(at: old, to: new)) != nil { continue }
            try? fm.removeItem(at: old)
        }
        let sounds = root.appendingPathComponent("Sounds", isDirectory: true)
        try? fm.createDirectory(at: sounds, withIntermediateDirectories: true)
        let files = (try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("um-") && file.pathExtension == "mp3" {
            let dest = sounds.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: dest.path) || (try? fm.moveItem(at: file, to: dest)) == nil {
                try? fm.removeItem(at: file)
            }
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    static func bytes() -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return 0 }
        var sum: Int64 = 0
        for case let f as URL in e {
            let v = try? f.resourceValues(forKeys: Set(keys))
            sum += Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
        return sum
    }
}
