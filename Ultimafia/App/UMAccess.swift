import Foundation
import AVFoundation

/// Cloudflare Access service token for the .gg backends (Z enters it on the Z page; Keychain, device-only).
/// Headers go ONLY to https/wss hosts under ultimafia.gg, never to .com or third parties.
nonisolated enum UMAccess {
    private static let service = "VCCCLLC.Ultimafia.cfaccess"
    private static let cache = UMLocked<(id: String, secret: String)?>(load())

    private static func load() -> (id: String, secret: String)? {
        guard let i = UMKeychain.get(service: service, account: "id").flatMap({ String(data: $0, encoding: .utf8) }),
              let s = UMKeychain.get(service: service, account: "secret").flatMap({ String(data: $0, encoding: .utf8) }),
              !i.isEmpty, !s.isEmpty else { return nil }
        return (i, s)
    }

    static var clientId: String? { cache.withLock { $0?.id } }
    static var isSet: Bool { cache.withLock { $0 != nil } }

    static func save(id: String, secret: String) {
        let i = id.trimmingCharacters(in: .whitespacesAndNewlines), s = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !i.isEmpty, !s.isEmpty else { return }
        UMKeychain.set(Data(i.utf8), service: service, account: "id", synced: false)
        UMKeychain.set(Data(s.utf8), service: service, account: "secret", synced: false)
        cache.withLock { $0 = (i, s) }
    }

    static func clear() {
        UMKeychain.delete(service: service, account: "id")
        UMKeychain.delete(service: service, account: "secret")
        cache.withLock { $0 = nil }
    }

    static func applies(to url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased(),
              ["https", "wss"].contains(url.scheme?.lowercased() ?? "") else { return false }
        return host == "ultimafia.gg" || host.hasSuffix(".ultimafia.gg")
    }

    static func headers(for url: URL?) -> [String: String] {
        guard applies(to: url), let c = cache.withLock({ $0 }) else { return [:] }
        return ["CF-Access-Client-Id": c.id, "CF-Access-Client-Secret": c.secret]
    }

    static func apply(_ req: inout URLRequest) {
        for (k, v) in headers(for: req.url) { req.setValue(v, forHTTPHeaderField: k) }
    }

    static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url); apply(&r); return r
    }

    /// Remote AVPlayer media with the headers.
    static func asset(_ url: URL) -> AVURLAsset {
        let h = headers(for: url)
        return h.isEmpty ? AVURLAsset(url: url) : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": h])
    }
}
