import Foundation
import Observation

/// Viewer-side site settings the app honors (same keys as user/settings/data):
/// disableAnimatedAvatars, ignoreTextColor, ignoreNameFonts, ignoreDeathSounds.
/// Synced from the signed-in user's settings, updated live when toggled in Advanced Settings,
/// and persisted in UserDefaults so they apply at launch before user info loads.
@Observable
final class UMViewerPrefs {
    static let shared = UMViewerPrefs()
    static let keys = ["disableAnimatedAvatars", "ignoreTextColor", "ignoreNameFonts", "ignoreDeathSounds"]

    var disableAnimatedAvatars: Bool { didSet { save("disableAnimatedAvatars", disableAnimatedAvatars) } }
    var ignoreTextColor: Bool { didSet { save("ignoreTextColor", ignoreTextColor) } }
    var ignoreNameFonts: Bool { didSet { save("ignoreNameFonts", ignoreNameFonts) } }
    var ignoreDeathSounds: Bool { didSet { save("ignoreDeathSounds", ignoreDeathSounds) } }
    /// The viewer's own user id (own avatar keeps animating, like the site's "other users'" wording).
    var myUserId: String?

    private init() {
        let d = UserDefaults.standard
        disableAnimatedAvatars = d.bool(forKey: "um.pref.disableAnimatedAvatars")
        ignoreTextColor = d.bool(forKey: "um.pref.ignoreTextColor")
        ignoreNameFonts = d.bool(forKey: "um.pref.ignoreNameFonts")
        ignoreDeathSounds = d.bool(forKey: "um.pref.ignoreDeathSounds")
    }

    private func save(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: "um.pref.\(key)")
    }

    static func flag(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let s = any as? String { return s == "true" }
        if let n = any as? NSNumber { return n.boolValue }
        return false
    }

    func set(_ key: String, _ value: Bool) {
        switch key {
        case "disableAnimatedAvatars": if disableAnimatedAvatars != value { disableAnimatedAvatars = value }
        case "ignoreTextColor": if ignoreTextColor != value { ignoreTextColor = value }
        case "ignoreNameFonts": if ignoreNameFonts != value { ignoreNameFonts = value }
        case "ignoreDeathSounds": if ignoreDeathSounds != value { ignoreDeathSounds = value }
        default: break
        }
    }

    /// Apply from a user info / settings blob. Missing keys count as false (site default).
    func apply(user: UserInfo?) {
        guard let user else { return }
        myUserId = user.id
        guard let st = user.settings?.asAny as? [String: Any] else { return }
        for k in Self.keys { set(k, Self.flag(st[k])) }
    }
}
