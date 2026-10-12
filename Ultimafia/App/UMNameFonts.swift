import SwiftUI
import CoreText
import Observation

/// Registers the cosmetic name fonts (web PR #2928 `settings.nameFont`). Bundled in Fonts/; falls back to ultimafia.com.
/// The site serves them under content-hashed paths, so we read the @font-face rules from the
/// live stylesheet, download each face once, cache it on disk, and register it process-wide.
@Observable
final class UMNameFonts {
    static let shared = UMNameFonts()

    /// nameFont key -> CSS font-family declared by the site.
    private static let webFamilies: [String: String] = [
        "slab": "RobotoSlab", "mono": "RobotoMono", "poppins": "Poppins",
        "bettynoir": "BettyNoir", "autophobia": "Autophobia", "spooky": "Spooky", "nabla": "Nabla",
    ]
    /// Fonts that ship with iOS, matching the web stacks directly.
    private static let systemFamilies: [String: String] = [
        "georgia": "Georgia", "trebuchet": "TrebuchetMS", "verdana": "Verdana",
    ]

    /// nameFont key -> registered PostScript name.
    private(set) var registered: [String: String] = [:]
    @ObservationIgnored private var started = false

    private var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UMNameFonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func loadIfNeeded() {
        guard !started else { return }
        started = true
        Task { await load() }
    }

    func postScriptName(for key: String) -> String? {
        let k = key.lowercased()
        return registered[k] ?? Self.systemFamilies[k]
    }

    private func load() async {
        // Bundled copies (Fonts/<CSS family>.ttf) are the primary source.
        for (key, family) in Self.webFamilies {
            if let url = Bundle.main.url(forResource: family, withExtension: "ttf"),
               let data = try? Data(contentsOf: url) { register(data, key: key) }
        }
        guard registered.count < Self.webFamilies.count else { return }
        // Fallback for any bundled face that is missing: disk cache, then the live site.
        // Cached files first so names render correctly offline / before the network returns.
        var cachedByFamily: [String: URL] = [:]
        if let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
            for f in files { cachedByFamily[f.deletingPathExtension().lastPathComponent] = f }
        }
        for (key, family) in Self.webFamilies where registered[key] == nil {
            if let file = cachedByFamily[family], let data = try? Data(contentsOf: file) { register(data, key: key) }
        }
        guard let urls = try? await fetchFontFaceURLs() else { return }
        for (key, family) in Self.webFamilies where registered[key] == nil {
            guard let url = urls[family],
                  let (data, resp) = try? await URLSession.shared.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
            if register(data, key: key) {
                try? data.write(to: cacheDir.appendingPathComponent(family + ".ttf"), options: .atomic)
            }
        }
    }

    @discardableResult
    private func register(_ data: Data, key: String) -> Bool {
        guard let provider = CGDataProvider(data: data as CFData),
              let cgFont = CGFont(provider),
              let ps = cgFont.postScriptName as String? else { return false }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterGraphicsFont(cgFont, &error) {
            // Already registered (e.g. second load) is fine; anything else is a bad file.
            guard UIFont(name: ps, size: 12) != nil else { return false }
        }
        registered[key] = ps
        return true
    }

    /// Reads the site's stylesheets and returns CSS family -> absolute font URL.
    private func fetchFontFaceURLs() async throws -> [String: URL] {
        let base = UMConfig.siteBase
        let (htmlData, _) = try await URLSession.shared.data(from: base)
        let html = String(decoding: htmlData, as: UTF8.self)
        let hrefs = matches(#"href="([^"]+\.css)""#, in: html)
        var out: [String: URL] = [:]
        for href in hrefs {
            guard let cssURL = URL(string: href, relativeTo: base),
                  let (cssData, _) = try? await URLSession.shared.data(from: cssURL) else { continue }
            let css = String(decoding: cssData, as: UTF8.self)
            for block in matches(#"@font-face\s*\{([^}]*)\}"#, in: css) {
                guard let fam = matches(#"font-family:\s*["']?([^;"']+)"#, in: block).first,
                      let src = matches(#"url\(["']?([^)"']+)"#, in: block).first,
                      let url = URL(string: src, relativeTo: cssURL)?.absoluteURL else { continue }
                out[fam.trimmingCharacters(in: .whitespaces)] = url
            }
        }
        return out
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }
}
