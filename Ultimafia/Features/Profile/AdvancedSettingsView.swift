import SwiftUI
import UIKit

// Mirrors the website's Settings page (react_main/src/pages/User/Settings.jsx):
// tabs Site, User, Game, Account, Cookies, Family in the site's order.
//
// Endpoints (routes/user.js, routes/vanityUrl.js, routes/family.js):
//   GET  user/settings/data                 current values (flat settings + username/pronouns/birthday/vanityUrl)
//   POST user/settings/update {prop,value}  every toggle / picker / color (same as the site's onSettingChange)
//   POST user/name {name, code:""}          POST user/pronouns {pronouns}
//   POST user/birthday {date:"YYYY-MM-DD"}  DELETE user/birthday
//   POST user/youtube {link}                POST user/deathMessage {deathMessage}
//   POST vanityUrl {vanityUrl}              DELETE vanityUrl
//   DELETE user/profileBackground | user/forumBanner | user/deathSound
//   POST user/delete                        (account deletion; double-confirmed, never auto-called)
//   GET  family/user/family                 POST family/create {name}
//   POST family/:id/media {link,autoplay,collapse}
//   POST family/:id/backgroundRepeatMode {backgroundRepeatMode}
//   DELETE family/:id/banner | family/:id/background
//   POST family/:id/transferLeadership {newLeaderId}   POST family/:id/leave
//   DELETE family/:id                       (family deletion; double-confirmed, never auto-called)
// Uploads are native (UMUploads.swift): Photos/Files → crop → resize/compress → the same multipart
// endpoint and field as the site; the website stays available as a fallback on each row.

/// Settings that only change the website client (rendered/filtered in the browser) and that the app
/// doesn't honor. Kept in code, hidden in the app. Flip to true to show them again.
enum UMWebsiteOnlySettings {
    static let show = false
}

enum AdvancedSettingsTab: String, CaseIterable, Identifiable {
    case site = "Site", user = "User", game = "Game", account = "Account", cookies = "Cookies", family = "Family"
    var id: String { rawValue }
}

@MainActor @Observable
final class AdvancedSettingsModel {
    var values: [String: Any] = [:]
    var family: [String: Any]?
    var familyMembers: [[String: Any]] = []
    var loaded = false
    var errorMessage: String?
    var notice: String?

    func load() async {
        do {
            let any = try await APIClient.shared.jsonObject("user/settings/data")
            values = any as? [String: Any] ?? [:]
            loaded = true
        } catch {
            errorMessage = Self.text(error)
        }
        await loadFamily()
    }

    func loadFamily() async {
        let any = try? await APIClient.shared.jsonObject("family/user/family")
        family = (any as? [String: Any])?["family"] as? [String: Any]
        if let id = family?["id"] as? String,
           let blob = try? await APIClient.shared.familyProfile(id) {
            familyMembers = blob["members"] as? [[String: Any]] ?? []
        } else {
            familyMembers = []
        }
    }

    func bool(_ k: String) -> Bool {
        if let b = values[k] as? Bool { return b }
        if let s = values[k] as? String { return s == "true" }
        if let n = values[k] as? NSNumber { return n.boolValue }
        return false
    }

    func string(_ k: String, _ fallback: String = "") -> String {
        if let s = values[k] as? String, s != "undefined", s != "null" { return s }
        if let n = values[k] as? NSNumber { return n.stringValue }
        return fallback
    }

    /// The site's onSettingChange: optimistic local update, POST user/settings/update, revert on error.
    func set(_ prop: String, _ value: Any, after: (() async -> Void)? = nil) async {
        let old = values[prop]
        values[prop] = value
        do {
            try await APIClient.shared.postStatus("user/settings/update", json: ["prop": prop, "value": value])
            await after?()
        } catch {
            values[prop] = old
            errorMessage = Self.text(error)
        }
    }

    /// Generic call used for save/clear/remove buttons. Returns true on success.
    @discardableResult
    func call(_ method: String, _ path: String, _ body: [String: Any]? = nil, success: String? = nil) async -> Bool {
        do {
            try await APIClient.shared.request(method, path: path, query: [:], body: body ?? (method == "POST" ? [:] : nil))
            if let success { notice = success }
            return true
        } catch {
            errorMessage = Self.text(error)
            return false
        }
    }

    static func text(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

struct AdvancedSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: AdvancedSettingsTab = .site
    @State private var model = AdvancedSettingsModel()

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            List {
                if !model.loaded {
                    HStack { Spacer(); ProgressView().tint(UMTheme.blood); Spacer() }
                        .listRowBackground(Color.clear)
                } else {
                    switch tab {
                    case .site: SiteSettingsTab(model: model)
                    case .user: UserSettingsTab(model: model)
                    case .game: GameSettingsTab(model: model)
                    case .account: AccountSettingsTab(model: model)
                    case .cookies: CookieSettingsTab()
                    case .family: FamilySettingsTab(model: model)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(UMTheme.bg.ignoresSafeArea())
        .navigationTitle("Advanced Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .alert("Couldn't save", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Saved", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.notice ?? "")
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AdvancedSettingsTab.allCases) { t in
                    let selected = t == tab
                    Button { tab = t } label: {
                        Text(t.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selected ? UMTheme.elevated : UMTheme.card, in: Capsule())
                            .overlay(Capsule().stroke(selected ? UMTheme.blood : UMTheme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(UMTheme.bg)
    }
}

// MARK: - Shared helpers

private extension UserInfo {
    var itemsDict: [String: Any] { itemsOwned?.asAny as? [String: Any] ?? [:] }
    func owns(_ key: String) -> Bool {
        let v = itemsDict[key]
        if let b = v as? Bool { return b }
        if let n = v as? Int { return n > 0 }
        if let n = v as? Double { return n > 0 }
        if let a = v as? [Any] { return !a.isEmpty }
        if let s = v as? String { return !s.isEmpty && s != "0" && s != "false" }
        return false
    }
    func hasPerm(_ key: String) -> Bool {
        let p = perms?.asAny as? [String: Any] ?? [:]
        if let b = p[key] as? Bool { return b }
        if let n = p[key] as? Int { return n > 0 }
        return false
    }
}

private struct UMOption: Identifiable, Hashable {
    var label: String
    var value: String
    var id: String { value }
}

private func opts(_ pairs: [(String, String)]) -> [UMOption] { pairs.map { UMOption(label: $0.0, value: $0.1) } }

private let shopHint = "Buy this in the Shop to enable it."

private struct SettingToggle: View {
    let model: AdvancedSettingsModel
    let title: String
    let prop: String
    var info: String?
    var disabled = false
    var after: (() async -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: Binding<Bool>(
                get: { model.bool(prop) },
                set: { v in Task { await model.set(prop, v, after: after) } }
            ))
            .tint(UMTheme.blood)
            .disabled(disabled)
            if let info { Text(info).font(.footnote).foregroundStyle(UMTheme.muted) }
        }
        .listRowBackground(UMTheme.card)
    }
}

private struct SettingPicker: View {
    let model: AdvancedSettingsModel
    let title: String
    let prop: String
    let options: [UMOption]
    var fallback: String
    var info: String?
    var disabled = false
    var after: (() async -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(title, selection: Binding<String>(
                get: {
                    let v = model.string(prop, fallback)
                    return options.contains { $0.value == v } ? v : fallback
                },
                set: { v in Task { await model.set(prop, v, after: after) } }
            )) {
                ForEach(options) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .disabled(disabled)
            if let info { Text(info).font(.footnote).foregroundStyle(UMTheme.muted) }
            if disabled { Text(shopHint).font(.footnote).foregroundStyle(UMTheme.muted) }
        }
        .listRowBackground(UMTheme.card)
    }
}

/// Color input: debounced save of #RRGGBB; optional Reset to `resetValue` (site's Reset button).
private struct SettingColor: View {
    let model: AdvancedSettingsModel
    let title: String
    let prop: String
    var defaultHex: String
    var resetValue: String?
    var info: String?
    var disabled = false
    var after: (() async -> Void)?
    @State private var pending: String?

    private var current: String {
        let v = model.string(prop)
        return (v.isEmpty || v == "none") ? "" : v
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ColorPicker(title, selection: Binding(
                    get: { Color(umHex: pending ?? (current.isEmpty ? defaultHex : current)) ?? .white },
                    set: { pending = $0.umHex }
                ), supportsOpacity: false)
                .disabled(disabled)
                if let resetValue, !current.isEmpty, current != resetValue, !disabled {
                    Button("Reset") {
                        pending = nil
                        Task { await model.set(prop, resetValue, after: after) }
                    }
                    .buttonStyle(.borderless)
                    .tint(UMTheme.blood)
                }
            }
            if let info { Text(info).font(.footnote).foregroundStyle(UMTheme.muted) }
            if disabled { Text(shopHint).font(.footnote).foregroundStyle(UMTheme.muted) }
        }
        .listRowBackground(UMTheme.card)
        .task(id: pending) {
            guard let hex = pending else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            if hex.lowercased() != current.lowercased() { await model.set(prop, hex, after: after) }
            pending = nil
        }
    }
}

/// Text input with an explicit Save (and optional Clear), like the site's saveBtn/clearBtn fields.
private struct SettingTextSave: View {
    let title: String
    let initial: String
    var placeholder = ""
    var info: String?
    var disabled = false
    var multiline = false
    var maxLength: Int?
    var onSave: (String) -> Void
    var onClear: (() -> Void)?
    @State private var text: String?

    var body: some View {
        let binding = Binding(get: { text ?? initial }, set: { v in text = maxLength.map { String(v.prefix($0)) } ?? v })
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Group {
                if multiline {
                    TextField(placeholder, text: binding, axis: .vertical).lineLimit(2...5)
                } else {
                    TextField(placeholder, text: binding)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(8)
            .background(UMTheme.elevated, in: RoundedRectangle(cornerRadius: 8))
            .disabled(disabled)
            HStack {
                if let maxLength { Text("\((text ?? initial).count)/\(maxLength)").font(.caption).foregroundStyle(UMTheme.muted) }
                Spacer()
                if let onClear {
                    Button("Clear", role: .destructive) { onClear() }
                        .buttonStyle(.borderless)
                        .disabled(disabled)
                }
                Button("Save") { onSave((text ?? initial).trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .buttonStyle(.borderless)
                    .tint(UMTheme.blood)
                    .disabled(disabled || (text ?? initial) == initial)
            }
            if let info { Text(info).font(.footnote).foregroundStyle(UMTheme.muted) }
            if disabled { Text(shopHint).font(.footnote).foregroundStyle(UMTheme.muted) }
        }
        .listRowBackground(UMTheme.card)
        .onChange(of: initial) { _, _ in text = nil }
    }
}

/// Native upload row: picker control, optional Remove, help text, and an "Open website" fallback.
private struct UploadRow<Control: View>: View {
    let title: String
    let sitePath: String
    var info: String?
    var removeTitle: String?
    var onRemove: (() -> Void)?
    @ViewBuilder var control: () -> Control
    @State private var browser: UMBrowserItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack {
                control()
                Spacer()
                if let onRemove {
                    Button(removeTitle ?? "Remove", role: .destructive) { onRemove() }.buttonStyle(.borderless)
                }
            }
            if let info { Text(info).font(.footnote).foregroundStyle(UMTheme.muted) }
            Button("Or use the website") { browser = UMBrowserItem(url: URL(string: "https://ultimafia.com\(sitePath)")!) }
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(UMTheme.muted)
        }
        .buttonStyle(.borderless)
        .listRowBackground(UMTheme.card)
        .sheet(item: $browser) { item in
            UMInAppBrowser(url: item.url, shareSiteSession: true) { browser = nil }
        }
    }
}

/// Confirmation wrapper for single-step confirms (site's window.confirm).
private struct ConfirmAction: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var button: String
    var destructive = true
    var action: () -> Void
}

private extension View {
    func confirmAction(_ item: Binding<ConfirmAction?>) -> some View {
        alert(item.wrappedValue?.title ?? "", isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }), presenting: item.wrappedValue) { c in
            Button(c.button, role: c.destructive ? .destructive : nil) { c.action() }
            Button("Cancel", role: .cancel) {}
        } message: { c in
            Text(c.message)
        }
    }
}

private extension Color {
    init?(umHex: String) {
        var s = umHex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var umHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", c(r), c(g), c(b))
    }
}

// MARK: - Site

private struct SiteSettingsTab: View {
    @Environment(AppModel.self) private var app
    let model: AdvancedSettingsModel

    var body: some View {
        let user = app.user
        Section {
            let url = "https://ultimafia.com/auth/login?ref=\(user?.id ?? "")"
            VStack(alignment: .leading, spacing: 6) {
                Text("Referral URL").font(.subheadline.weight(.semibold))
                Text(url).font(.footnote.monospaced()).foregroundStyle(UMTheme.roleMention).textSelection(.enabled)
                HStack {
                    Button("Copy") { UIPasteboard.general.string = url }.buttonStyle(.borderless).tint(UMTheme.blood)
                    if let link = URL(string: url) { ShareLink(item: link).buttonStyle(.borderless) }
                }
            }
            .listRowBackground(UMTheme.card)
            SettingToggle(model: model, title: "DMs from Friends Only", prop: "onlyFriendDMs")
            SettingToggle(model: model, title: "Disable Pokes", prop: "disablePokes")
        }
        if UMWebsiteOnlySettings.show {
        Section("Censors") {
            if !model.bool("disableAllCensors") {
                SettingToggle(model: model, title: "Disable PG-13 Censor", prop: "disablePg13Censor")
            }
            if user?.hasPerm("disableAllCensors") == true {
                SettingToggle(model: model, title: "Disable All Censors", prop: "disableAllCensors")
            }
        }
        if user?.hasPerm("viewDeleted") == true {
            Section {
                SettingToggle(model: model, title: "Hide Deleted Posts", prop: "hideDeleted")
            }
        }
        Section {
            SettingPicker(model: model, title: "Site Color Scheme", prop: "siteColorScheme",
                          options: opts([("System", "system"), ("Light", "light"), ("Dark", "dark")]), fallback: "system")
            SettingPicker(model: model, title: "Minimum WCAG contrast", prop: "minimumContrast",
                          options: opts([("None", "none"), ("3.5", "3.5"), ("7", "7")]), fallback: "none")
            SettingPicker(model: model, title: "Font size", prop: "fontSize",
                          options: opts([("System", "system"), ("16 pixels", "16"), ("18 pixels", "18"), ("20 pixels", "20"), ("24 pixels", "24")]), fallback: "system")
            SettingPicker(model: model, title: "Font", prop: "fontFamily",
                          options: opts([("Default (Roboto Slab)", "default"), ("System (system-ui)", "system"), ("Readable (Tahoma)", "readable")]), fallback: "default")
            SettingColor(model: model, title: "Custom Site Primary Color", prop: "customPrimaryColor", defaultHex: "#c23a2b",
                         resetValue: "none", disabled: !(user?.owns("customPrimaryColor") ?? false))
            SettingPicker(model: model, title: "Icon Filter", prop: "iconFilter",
                          options: opts([("None", "none"), ("High Contrast", "highContrast"), ("Elevated", "elevated"), ("Sepia", "sepia"),
                                         ("Green", "green"), ("Inverted", "inverted"), ("Grayscale", "grayscale"), ("Colorful", "colorful"),
                                         ("Upside Down", "upsideDown"), ("Hallucination", "hallucination"),
                                         ("Chromatic Aberration", "chromaticAberration"), ("Vaporwave", "vaporwave")]),
                          fallback: "none", disabled: !(user?.owns("iconFilter") ?? false))
            SettingToggle(model: model, title: "Experimental High DPI Correction", prop: "expHighDpiCorrection")
        } header: {
            Text("Appearance (website)")
        } footer: {
            Text("These change how ultimafia.com looks for you. The app keeps its own appearance.")
        }
        Section {
            SettingToggle(model: model, title: "Disable Snowstorm", prop: "disableSnowstorm",
                          info: "Turn off the snow effect during December (holiday season)")
            SettingToggle(model: model, title: "Disable All Media Autoplay", prop: "disableMediaAutoplay",
                          info: "When enabled, profile and family media players will not autoplay for you, even if the owner turned autoplay on.")
            SettingToggle(model: model, title: "Disable Animated Avatars", prop: "disableAnimatedAvatars",
                          info: "When enabled, other users' GIF/WebP avatars are shown as a still first frame.")
        }
        } // UMWebsiteOnlySettings.show
    }
}

// MARK: - User

private struct UserSettingsTab: View {
    @Environment(AppModel.self) private var app
    let model: AdvancedSettingsModel
    @State private var confirm: ConfirmAction?
    @State private var birthday = Date()
    @State private var birthdayTouched = false

    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        let user = app.user
        let customProfile = user?.owns("customProfile") ?? false
        Section {
            SettingTextSave(title: "Name", initial: model.string("username", user?.name ?? "")) { name in
                confirm = ConfirmAction(title: "Change username?", message: "Are you sure you wish to change your username?", button: "Change", destructive: false) {
                    Task {
                        if await model.call("POST", "user/name", ["name": name, "code": ""], success: "Username changed") {
                            model.values["username"] = name
                            await refreshUser()
                        }
                    }
                }
            }
            SettingTextSave(title: "Pronouns", initial: model.string("pronouns")) { p in
                Task {
                    if await model.call("POST", "user/pronouns", ["pronouns": p], success: "Pronouns changed") { model.values["pronouns"] = p }
                }
            }
            birthdayRow
        }
        Section("Profile") {
            UploadRow(title: "Avatar", sitePath: "/user/profile",
                      info: "Square crop, saved at 100×100 by the server (static max 1 MB). Animated GIF/WebP needs Animated Profile Picture from the Shop.") {
                UMImageUploadButton(spec: .avatar(animated: user?.owns("animatedAvatar") ?? false), label: "Upload Avatar", purge: UMUploadURLs.avatar(user?.id ?? "")) { await refreshUser() }
            }
            if customProfile || (user?.owns("animatedBanner") ?? false) {
                UploadRow(title: "Profile Banner", sitePath: "/user/profile",
                          info: "3:1 crop, saved at 900×300. Animated GIF/WebP (max 20 MB, frames ≤1800×600) needs Animated Profile Banner.") {
                    UMImageUploadButton(spec: .banner(animated: user?.owns("animatedBanner") ?? false), label: "Upload Banner", purge: UMUploadURLs.banner(user?.id ?? "")) { await refreshUser() }
                }
            }
            SettingColor(model: model, title: "Background Color", prop: "backgroundColor", defaultHex: "#535353", disabled: !customProfile)
            SettingTextSave(title: "Media URL", initial: model.string("youtube"), placeholder: "https://…",
                            info: "Supports YouTube, SoundCloud, Spotify, Vimeo, Invidious, and direct media files (mp3, mp4, webm, ogg)") { link in
                Task {
                    if await model.call("POST", "user/youtube", ["link": link], success: "Profile media changed") { model.values["youtube"] = link }
                }
            }
            if !model.string("youtube").isEmpty {
                SettingToggle(model: model, title: "Autoplay Media", prop: "autoplay")
                SettingToggle(model: model, title: "Collapse Media Player", prop: "collapseMedia",
                              info: "Starts the profile media player collapsed (arrow only).")
            }
            SettingPicker(model: model, title: "Banner Format", prop: "bannerFormat",
                          options: opts([("Tile", "tile"), ("Stretch", "stretch")]), fallback: "tile", disabled: !customProfile)
            SettingPicker(model: model, title: "Avatar shape", prop: "avatarShape",
                          options: opts([("Circle", "circle"), ("Square", "square")]), fallback: "circle",
                          disabled: !(user?.owns("avatarShape") ?? false))
            vanityRow(owned: user?.owns("vanityUrl") ?? false)
            if user?.owns("profileBackground") == true {
                UploadRow(title: "Profile Background", sitePath: "/user/settings/profile",
                          info: "Replaces the default diamond pattern on your profile page (max 5 MB, any shape).",
                          onRemove: {
                    confirm = ConfirmAction(title: "Remove background?", message: "Are you sure you wish to remove your profile background?", button: "Remove") {
                        Task { if await model.call("DELETE", "user/profileBackground", success: "Profile background removed") { await UMImageCache.shared.purge(UMUploadURLs.profileBackground(app.user?.id ?? "")) } }
                    }
                }) {
                    UMImageUploadButton(spec: .profileBackground, label: "Upload Background Image", purge: UMUploadURLs.profileBackground(app.user?.id ?? "")) { await model.load() }
                }
            }
            if user?.owns("forumBanner") == true {
                UploadRow(title: "Forum Banner", sitePath: "/user/settings/profile",
                          info: "Slim banner above your forum post header (5:1 crop, saved at 500×100, max 2 MB).",
                          onRemove: {
                    confirm = ConfirmAction(title: "Remove forum banner?", message: "Are you sure you wish to remove your forum banner?", button: "Remove") {
                        Task { if await model.call("DELETE", "user/forumBanner", success: "Forum banner removed") { await UMImageCache.shared.purge(UMUploadURLs.forumBanner(app.user?.id ?? "")) } }
                    }
                }) {
                    UMImageUploadButton(spec: .forumBanner, label: "Upload Forum Banner", purge: UMUploadURLs.forumBanner(app.user?.id ?? "")) { await model.load() }
                }
            }
            if user?.owns("profileBackground") == true {
                SettingPicker(model: model, title: "Background Display Mode", prop: "backgroundRepeatMode",
                              options: opts([("Checker", "checker"), ("Stretch", "stretch")]), fallback: "checker",
                              info: "Checker (pattern) or Stretch (full screen).")
            }
            if user?.isDonor == true {
                SettingToggle(model: model, title: "Hide Donor Badge", prop: "hideDonorBadge",
                              info: "Hide the donor heart badge on your profile and posts. You will remain in the Donor group and on the Donors page.",
                              after: { await refreshUser() })
            }
        }
        Section("Stat Hiding") {
            SettingToggle(model: model, title: "Hide Statistics", prop: "hideStatistics")
            SettingToggle(model: model, title: "Hide Karma", prop: "hideKarma")
            SettingToggle(model: model, title: "Hide Misfortune", prop: "hidePointsNegative")
            SettingToggle(model: model, title: "Hide Join Date", prop: "hideJoinDate")
        }
        .confirmAction($confirm)
    }

    private var birthdayRow: some View {
        let saved = model.string("birthday")
        let savedDate = Self.ymd.date(from: String(saved.prefix(10)))
        return VStack(alignment: .leading, spacing: 6) {
            DatePicker("Birthday", selection: Binding(get: { birthdayTouched ? birthday : (savedDate ?? birthday) },
                                                     set: { birthday = $0; birthdayTouched = true }),
                       displayedComponents: .date)
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            HStack {
                Spacer()
                if savedDate != nil {
                    Button("Clear", role: .destructive) {
                        confirm = ConfirmAction(title: "Clear birthday?", message: "Are you sure you want to clear your birthday?", button: "Clear") {
                            Task {
                                if await model.call("DELETE", "user/birthday", success: "Birthday cleared") {
                                    model.values["birthday"] = nil
                                    birthdayTouched = false
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }
                Button("Save") {
                    let date = Self.ymd.string(from: birthday)
                    confirm = ConfirmAction(title: "Change birthday?", message: "Are you sure you wish to change your birthday?", button: "Save", destructive: false) {
                        Task {
                            if await model.call("POST", "user/birthday", ["date": date], success: "Birthday set") {
                                model.values["birthday"] = date
                                birthdayTouched = false
                            }
                        }
                    }
                }
                .buttonStyle(.borderless)
                .tint(UMTheme.blood)
                .disabled(!birthdayTouched)
            }
            Text("Other users will know when it's your birthday because your text will be rainbow colored. It can only be changed once.")
                .font(.footnote).foregroundStyle(UMTheme.muted)
        }
        .listRowBackground(UMTheme.card)
    }

    private func vanityRow(owned: Bool) -> some View {
        SettingTextSave(title: "Vanity URL", initial: model.string("vanityUrl"), info: "Set a custom URL for your profile (1-20 characters, letters, numbers, and hyphens only)",
                        disabled: !owned, maxLength: 20, onSave: { v in
            guard (1...20).contains(v.count), v.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else {
                model.errorMessage = "Vanity URL must be 1-20 characters: letters, numbers, and hyphens only."
                return
            }
            Task { if await model.call("POST", "vanityUrl", ["vanityUrl": v], success: "Vanity URL changed") { model.values["vanityUrl"] = v } }
        }, onClear: model.string("vanityUrl").isEmpty ? nil : {
            confirm = ConfirmAction(title: "Clear vanity URL?", message: "Are you sure you want to clear your vanity URL?", button: "Clear") {
                Task { if await model.call("DELETE", "vanityUrl", success: "Vanity URL cleared") { model.values["vanityUrl"] = "" } }
            }
        })
    }

    private func refreshUser() async {
        if let info = try? await APIClient.shared.userInfo() { app.user = info }
    }
}

// MARK: - Game

private struct GameSettingsTab: View {
    @Environment(AppModel.self) private var app
    let model: AdvancedSettingsModel
    @State private var confirm: ConfirmAction?

    private let colorInfo = "Leave default (use Reset) for no custom color. Custom colors must have good contrast in both light and dark themes (minimum 3:1 ratio)."

    var body: some View {
        let user = app.user
        let textColors = user?.owns("textColors") ?? false
        let animated = (user?.owns("animatedNameColor") ?? false) && textColors
        let tricolor = user?.owns("tricolorAnimatedGradient") ?? false
        let anim = model.string("animatedNameColor", "none")
        let gradientMode = anim == "gradient" || anim == "tricolor"
        let refresh: () async -> Void = { if let info = try? await APIClient.shared.userInfo() { app.user = info } }
        Section("Name & Text") {
            if !gradientMode {
                SettingColor(model: model, title: "Name Color", prop: "nameColor", defaultHex: "#ffffff", resetValue: "",
                             info: colorInfo, disabled: !textColors, after: refresh)
            }
            SettingColor(model: model, title: "Text Color", prop: "textColor", defaultHex: "#ffffff", resetValue: "",
                         info: colorInfo, disabled: !textColors, after: refresh)
            SettingPicker(model: model, title: "Name Font (player list only)", prop: "nameFont",
                          options: opts([("Default", "default"), ("Slab (Roboto Slab)", "slab"), ("Mono (Roboto Mono)", "mono"), ("Poppins", "poppins"),
                                         ("Georgia", "georgia"), ("Trebuchet", "trebuchet"), ("Verdana", "verdana"), ("Comic Sans", "comic"),
                                         ("Betty Noir", "bettynoir"), ("Autophobia", "autophobia"), ("Spooky", "spooky"), ("Nabla", "nabla")]),
                          fallback: "default",
                          info: "Applies to your name on the player list and in chat nameplates (not message text).",
                          disabled: !(user?.owns("nameFont") ?? false), after: refresh)
            if animated {
                let animOpts = opts([("None", "none"), ("Pulse", "pulse"), ("Glow", "glow"), ("Rainbow", "rainbow"),
                                     ("Patriotic", "patriotic"), ("Gradient (2 colors)", "gradient")])
                    + (tricolor ? [UMOption(label: "Gradient (3 colors)", value: "tricolor")] : [])
                SettingPicker(model: model, title: "Animated Name Color (player list only)", prop: "animatedNameColor",
                              options: animOpts, fallback: "none",
                              info: "Applies to your name on the player list and in chat nameplates (not message text). Gradient/Tricolor use the color pickers below.",
                              after: refresh)
                if gradientMode {
                    SettingColor(model: model, title: "Gradient Color A", prop: "nameGradientColorA", defaultHex: "#ff0040",
                                 info: "First color of the animated name gradient (order: 1 → 2 → 3).", after: refresh)
                    SettingColor(model: model, title: "Gradient Color B", prop: "nameGradientColorB", defaultHex: "#00c2ff",
                                 info: "Second color of the animated name gradient.", after: refresh)
                }
                if anim == "tricolor" && tricolor {
                    SettingColor(model: model, title: "Gradient Color C", prop: "nameGradientColorC", defaultHex: "#3dff6a",
                                 info: "Third color of the tricolor gradient (order: 1 → 2 → 3).", after: refresh)
                }
            }
            SettingPicker(model: model, title: "In-game Avatar Shape", prop: "gameAvatarShape",
                          options: opts([("Circle", "circle"), ("Square", "square")]), fallback: "circle",
                          info: "Shape of your avatar in the player list, chat, lobby, and spectator lists. Your profile avatar shape is separate.",
                          disabled: !(user?.owns("avatarShape") ?? false), after: refresh)
        }
        Section("Display") {
            if UMWebsiteOnlySettings.show {
                SettingToggle(model: model, title: "Ignore Custom Text Color", prop: "ignoreTextColor")
                SettingToggle(model: model, title: "Ignore Custom Name Font", prop: "ignoreNameFonts",
                              info: "When enabled, all usernames use the default font. Name colors and animations are unchanged.")
                SettingToggle(model: model, title: "Accessible Name Colors", prop: "accessibleNameColors",
                              info: "Shows each player's custom name color in a circle beside their name. Names and message text use black or white for readability based on your theme.")
            }
            // Server-side (Games/core/User.js): the game server skips protips, so the app benefits too.
            SettingToggle(model: model, title: "Disable Protips", prop: "disableProTips")
        }
        Section("Death") {
            SettingTextSave(title: "Death Message (max 150 chars)", initial: model.string("deathMessage"), placeholder: "${name} was …",
                            info: "Must include ${name} as a placeholder for your username. Each save uses one Death Message change from the Shop.",
                            disabled: !(user?.owns("deathMessageEnabled") ?? false), multiline: true, maxLength: 150) { msg in
                guard msg.contains("${name}") else {
                    model.errorMessage = "You must use ${name} in the death message as a placeholder for your username."
                    return
                }
                Task { if await model.call("POST", "user/deathMessage", ["deathMessage": msg], success: "Death message changed") { model.values["deathMessage"] = msg } }
            }
            if user?.owns("deathSoundEnabled") == true {
                UploadRow(title: "Custom Death Sound", sitePath: "/user/settings/game",
                          info: "Played to everyone in the lobby when you die. MP3/WAV (OGG/WebM via the website), up to 10 MB; trimmed to 5 seconds.",
                          onRemove: {
                    confirm = ConfirmAction(title: "Remove death sound?", message: "Your custom death sound will be removed.", button: "Remove") {
                        Task { await model.call("DELETE", "user/deathSound", success: "Death sound removed") }
                    }
                }) {
                    UMDeathSoundUploadButton { await model.load() }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Death Sound").foregroundStyle(UMTheme.muted)
                    Text("Purchase Custom Death Sound in the Shop.").font(.footnote).foregroundStyle(UMTheme.muted)
                }
                .listRowBackground(UMTheme.card)
            }
            if UMWebsiteOnlySettings.show {
                SettingToggle(model: model, title: "Ignore all Death Sounds", prop: "ignoreDeathSounds",
                              info: "When enabled, you will not hear custom death sounds from other players in games.")
            }
        }
        Section {
            NavigationLink("Order Custom Emojis & Stickers") { CustomMediaOrderView() }
                .listRowBackground(UMTheme.card)
            CustomMediaUploadRows(model: model)
        } header: {
            Text("Custom Emotes & Stickers")
        }
        .confirmAction($confirm)
    }
}

// MARK: - Account

private struct AccountSettingsTab: View {
    @Environment(AppModel.self) private var app
    let model: AdvancedSettingsModel
    @State private var email = ""
    @State private var sending = false
    @State private var confirmDelete = false
    @State private var typingConfirm = false
    @State private var typedName = ""

    var body: some View {
        Section {
            TextField("Email Address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(UMTheme.card)
            Button {
                Task {
                    sending = true
                    defer { sending = false }
                    do {
                        try await FirebaseAuth.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
                        model.notice = "Password reset email has been sent."
                        email = ""
                    } catch {
                        model.errorMessage = "Failed to send password reset email."
                    }
                }
            } label: {
                if sending { ProgressView() } else { Text("Reset Password") }
            }
            .disabled(sending || email.trimmingCharacters(in: .whitespaces).isEmpty)
            .listRowBackground(UMTheme.card)
        } header: {
            Text("Password")
        }
        Section {
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete Account", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(UMTheme.mafia)
            }
            .disabled(app.seatedGameId != nil)
            .listRowBackground(UMTheme.card)
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Permanently deletes your Ultimafia account: friends, notifications and your vanity URL are removed. This cannot be undone.")
        }
        // Step 1: destructive alert. Step 2: type the username exactly.
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Continue", role: .destructive) { typedName = ""; typingConfirm = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you wish to DELETE your account? This cannot be undone.")
        }
        .alert("Type your username to confirm", isPresented: $typingConfirm) {
            TextField(app.user?.name ?? "Username", text: $typedName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Delete Account", role: .destructive) {
                guard let name = app.user?.name, !name.isEmpty, typedName == name else {
                    model.errorMessage = "The username didn't match. Your account was not deleted."
                    return
                }
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter \(app.user?.name ?? "your username") to permanently delete this account.")
        }
    }

    private func deleteAccount() async {
        let id = app.user?.id
        guard await model.call("POST", "user/delete") else { return }
        if let id { app.removeSavedAccount(id) }
        await app.signOut()
    }
}

// MARK: - Cookies

private struct CookieSettingsTab: View {

    var body: some View {
        Section {
            Text("On the website, cookie preferences are stored in your browser and apply to that device only. The app doesn't use browser cookies for tracking, so here is what each category means in the app.")
                .font(.footnote).foregroundStyle(UMTheme.muted)
                .listRowBackground(UMTheme.card)
            NavigationLink("Privacy Policy") { UMLegalView(title: "Privacy Policy", markdown: UMLegalText.privacyPolicy) }
                .listRowBackground(UMTheme.card)
            NavigationLink("Terms of Service") { UMLegalView(title: "Terms of Service", markdown: UMLegalText.termsOfService) }
                .listRowBackground(UMTheme.card)
        } header: {
            Text("Cookie Preferences")
        }
        Section {
            row("Essential", on: true, "Required for the app to work: your sign-in session with ultimafia.com. These cannot be disabled; signing out removes them.")
            row("Analytics", on: false, "The app doesn't include analytics (such as Google Analytics). Nothing to turn off.")
            row("Functional", on: true, "Your app preferences (chat layout, volumes, emoji order) are saved on this device in app settings, not in cookies. Change them in the You tab.")
        } footer: {
            Text("To change cookie choices for the website itself, use Settings > Cookies on ultimafia.com in your browser.")
        }
    }

    private func row(_ title: String, on: Bool, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("\(title) Cookies", isOn: .constant(on)).disabled(true).tint(UMTheme.blood)
            Text(detail).font(.footnote).foregroundStyle(UMTheme.muted)
        }
        .listRowBackground(UMTheme.card)
    }
}

// MARK: - Family

private struct FamilySettingsTab: View {
    @Environment(AppModel.self) private var app
    let model: AdvancedSettingsModel
    @State private var newFamilyName = ""
    @State private var mediaURL: String?
    @State private var mediaAutoplay: Bool?
    @State private var mediaCollapse: Bool?
    @State private var transferTo = ""
    @State private var confirm: ConfirmAction?
    @State private var deleteStep1 = false
    @State private var deleteStep2 = false
    @State private var typedFamilyName = ""

    private func s(_ k: String) -> String { model.family?[k] as? String ?? "" }
    private func b(_ k: String) -> Bool { (model.family?[k] as? Bool) ?? ((model.family?[k] as? NSNumber)?.boolValue ?? false) }
    private var perks: [String] { model.family?["perks"] as? [String] ?? [] }

    var body: some View {
        Group { content }.confirmAction($confirm)
    }

    @ViewBuilder
    private var content: some View {
        let fam = model.family
        let canCreate = app.user?.owns("createFamily") ?? false
        if fam == nil && !canCreate {
            Section("Family") {
                Text("No family.").foregroundStyle(UMTheme.muted).listRowBackground(UMTheme.card)
            }
        }
        if canCreate {
            Section {
                TextField("Enter family name", text: Binding(get: { newFamilyName }, set: { newFamilyName = String($0.prefix(20)) }))
                    .disabled(fam != nil)
                    .listRowBackground(UMTheme.card)
                Button("Create Family") {
                    let name = newFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { model.errorMessage = "Please enter a family name"; return }
                    guard name.count <= 20 else { model.errorMessage = "Family name must be 20 characters or less."; return }
                    Task {
                        if await model.call("POST", "family/create", ["name": name], success: "Family created successfully!") {
                            newFamilyName = ""
                            await model.loadFamily()
                        }
                    }
                }
                .disabled(fam != nil || newFamilyName.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowBackground(UMTheme.card)
            } header: {
                Text("Create Family")
            } footer: {
                Text(fam != nil ? "You're already in a family." : "\(newFamilyName.count)/20 characters. Set the family avatar on the family page or the website after creating.")
            }
        }
        if let fam {
            let id = s("id")
            Section {
                Button {
                    app.setPlayPath([.family(id: id, name: s("name"))])
                } label: {
                    HStack {
                        Text(b("isLeader") ? "You are the leader of" : "You are a member of").foregroundStyle(UMTheme.muted)
                        Text(s("name")).bold().foregroundStyle(UMTheme.blood)
                    }
                }
                .listRowBackground(UMTheme.card)
            } header: {
                Text("Manage Family")
            }
            if b("isLeader") {
                leaderSections(fam: fam, id: id)
            } else {
                Section {
                    Button("Leave Family", role: .destructive) {
                        confirm = ConfirmAction(title: "Leave family?", message: "Are you sure you want to leave this family? You will need to be re-invited to rejoin.", button: "Leave") {
                            Task { if await model.call("POST", "family/\(id)/leave", success: "You have left the family") { await model.loadFamily() } }
                        }
                    }
                    .listRowBackground(UMTheme.card)
                }
            }
        }
    }

    @ViewBuilder
    private func leaderSections(fam: [String: Any], id: String) -> some View {
        Section("Images") {
            UploadRow(title: "Family Avatar", sitePath: "/user/settings/family",
                      info: "Square crop, saved at 100×100 (static max 1 MB; animated needs the Animated Avatar perk, max 25 MB).") {
                UMImageUploadButton(spec: .familyAvatar(animated: perks.contains("familyAnimatedAvatar")), label: "Upload New Avatar", purge: UMUploadURLs.familyAvatar(id)) { await model.loadFamily() }
            }
            UploadRow(title: "Family Banner", sitePath: "/user/settings/family",
                      info: perks.contains("familyBanner")
                        ? "Banner for the family page, 3:1 crop saved at 900×300" + (perks.contains("familyAnimatedBanner") ? " (animation enabled, max 20 MB)." : " (max 5 MB).")
                        : "Your family must buy the Family Banner perk first.",
                      onRemove: b("banner") ? {
                confirm = ConfirmAction(title: "Remove banner?", message: "Remove the family banner?", button: "Remove") {
                    Task { if await model.call("DELETE", "family/\(id)/banner", success: "Family banner removed") { await UMImageCache.shared.purge(UMUploadURLs.familyBanner(id)); await model.loadFamily() } }
                }
            } : nil) {
                UMImageUploadButton(spec: .familyBanner(id: id, animated: perks.contains("familyAnimatedBanner")),
                                    label: perks.contains("familyAnimatedBanner") ? "Upload / Crop Banner" : "Upload Banner",
                                    disabled: !perks.contains("familyBanner"), purge: UMUploadURLs.familyBanner(id)) { await model.loadFamily() }
            }
            UploadRow(title: "Family Background", sitePath: "/user/settings/family",
                      info: "Replaces the default pattern on the family page (max 5 MB).",
                      onRemove: b("background") ? {
                confirm = ConfirmAction(title: "Remove background?", message: "Are you sure you wish to remove the family background?", button: "Remove") {
                    Task { if await model.call("DELETE", "family/\(id)/background", success: "Family background removed") { await UMImageCache.shared.purge(UMUploadURLs.familyBackground(id)); await model.loadFamily() } }
                }
            } : nil) {
                UMImageUploadButton(spec: .familyBackground(id: id), label: "Upload Background Image", purge: UMUploadURLs.familyBackground(id)) { await model.loadFamily() }
            }
            if b("background") {
                Picker("Background Display Mode", selection: Binding<String>(
                    get: { s("backgroundRepeatMode").isEmpty ? "checker" : s("backgroundRepeatMode") },
                    set: { mode in
                        Task {
                            if await model.call("POST", "family/\(id)/backgroundRepeatMode", ["backgroundRepeatMode": mode], success: "Background display mode updated") {
                                await model.loadFamily()
                            }
                        }
                    })) {
                    Text("Checker").tag("checker")
                    Text("Stretch").tag("stretch")
                }
                .pickerStyle(.menu)
                .tint(.white)
                .listRowBackground(UMTheme.card)
            }
        }
        Section {
            if perks.contains("familyMusicPlayer") {
                TextField("https://...", text: Binding(get: { mediaURL ?? s("mediaUrl") }, set: { mediaURL = $0 }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .listRowBackground(UMTheme.card)
                Toggle("Autoplay", isOn: Binding(get: { mediaAutoplay ?? b("mediaAutoplay") }, set: { mediaAutoplay = $0 }))
                    .tint(UMTheme.blood).listRowBackground(UMTheme.card)
                Toggle("Collapse player", isOn: Binding(get: { mediaCollapse ?? b("mediaCollapse") }, set: { mediaCollapse = $0 }))
                    .tint(UMTheme.blood).listRowBackground(UMTheme.card)
                Button("Save media") {
                    let body: [String: Any] = ["link": mediaURL ?? s("mediaUrl"),
                                               "autoplay": mediaAutoplay ?? b("mediaAutoplay"),
                                               "collapse": mediaCollapse ?? b("mediaCollapse")]
                    Task {
                        if await model.call("POST", "family/\(id)/media", body, success: "Family media saved") {
                            mediaURL = nil; mediaAutoplay = nil; mediaCollapse = nil
                            await model.loadFamily()
                        }
                    }
                }
                .listRowBackground(UMTheme.card)
            } else {
                Text("Buy the Family Music Player perk on the family page to enable this.")
                    .font(.footnote).foregroundStyle(UMTheme.muted).listRowBackground(UMTheme.card)
            }
        } header: {
            Text("Family Music Player")
        } footer: {
            if perks.contains("familyMusicPlayer") {
                Text("Same media types as profile (YouTube, SoundCloud, Spotify, Vimeo, direct files). Plays on the family page.")
            }
        }
        Section {
            let myId = app.user?.id
            let others = model.familyMembers.filter { ($0["id"] as? String) != myId }
            Picker("New leader", selection: $transferTo) {
                Text("Choose a member").tag("")
                ForEach(others.indices, id: \.self) { i in
                    let m = others[i]
                    Text(m["name"] as? String ?? "?").tag(m["id"] as? String ?? "")
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .listRowBackground(UMTheme.card)
            Button("Transfer Leadership") {
                guard !transferTo.isEmpty else { model.errorMessage = "Please select a family member"; return }
                let target = transferTo
                confirm = ConfirmAction(title: "Transfer leadership?", message: "Are you sure you want to transfer leadership? You will lose the ability to manage the family.", button: "Transfer") {
                    Task {
                        if await model.call("POST", "family/\(id)/transferLeadership", ["newLeaderId": target], success: "Leadership transferred successfully") {
                            transferTo = ""
                            await model.loadFamily()
                        }
                    }
                }
            }
            .disabled(transferTo.isEmpty)
            .listRowBackground(UMTheme.card)
        } header: {
            Text("Transfer Leadership")
        }
        Section {
            Button(role: .destructive) { deleteStep1 = true } label: {
                Label("Delete Family", systemImage: "exclamationmark.triangle.fill").foregroundStyle(UMTheme.mafia)
            }
            .listRowBackground(UMTheme.card)
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Deleting the family removes all members and cannot be undone.")
        }
        // Step 1: destructive alert. Step 2: type the family name exactly.
        .alert("Delete family?", isPresented: $deleteStep1) {
            Button("Continue", role: .destructive) { typedFamilyName = ""; deleteStep2 = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete your family? This will remove all members and cannot be undone.")
        }
        .alert("Type the family name to confirm", isPresented: $deleteStep2) {
            TextField(s("name"), text: $typedFamilyName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Delete Family", role: .destructive) {
                let name = s("name")
                guard !name.isEmpty, typedFamilyName == name else {
                    model.errorMessage = "The family name didn't match. The family was not deleted."
                    return
                }
                Task { if await model.call("DELETE", "family/\(id)", success: "Family deleted successfully") { await model.loadFamily() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter \(s("name")) to permanently delete it.")
        }
    }
}

// MARK: - Custom emote / sticker upload

/// Site Form emoteUpload / stickerUpload: name + image, slots from the Shop.
private struct CustomMediaUploadRows: View {
    @Environment(AppModel.self) private var app
    let model: AdvancedSettingsModel
    @State private var emoteName = ""
    @State private var stickerName = ""

    private func count(_ k: String) -> Int { (model.values[k] as? [String: Any])?.count ?? (model.values[k] as? [Any])?.count ?? 0 }
    private func item(_ k: String) -> Int {
        let v = (app.user?.itemsOwned?.asAny as? [String: Any])?[k]
        return (v as? Int) ?? Int((v as? Double) ?? 0)
    }
    private func nameError(_ n: String) -> String? {
        if n.isEmpty { return nil }
        if n.contains(" ") || n.contains(":") { return "Names may not have spaces or colons." }
        if n.count > 25 { return "Name is too long (max 25)." }
        return nil
    }

    var body: some View {
        let emoteSlots = item("customEmotes") + item("customEmotesExtra")
        let emotesUsed = count("customEmotes")
        let stickerSlots = item("customStickers")
        let stickersUsed = count("customStickers")
        UploadRow(title: "Upload Custom Emote", sitePath: "/user/settings/game",
                  info: nameError(emoteName) ?? "\(emotesUsed)/\(emoteSlots) emote slots used. Square crop; the server shrinks it to 30×30. Animated GIF/WebP allowed (under ~1.4 MB).") {
            HStack {
                TextField("emote name", text: $emoteName)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .frame(maxWidth: 140)
                UMImageUploadButton(spec: .emote(name: emoteName), label: "Choose Image",
                                    disabled: emoteName.isEmpty || nameError(emoteName) != nil || emotesUsed >= emoteSlots) {
                    emoteName = ""
                    await model.load()
                }
            }
        }
        UploadRow(title: "Upload Custom Sticker", sitePath: "/user/settings/game",
                  info: nameError(stickerName) ?? "\(stickersUsed)/\(stickerSlots) sticker slots used (buy more in the Shop, 10 coins each). GIF/PNG/JPEG/WebP, max 512×512.") {
            HStack {
                TextField("sticker name", text: $stickerName)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .frame(maxWidth: 140)
                UMImageUploadButton(spec: .sticker(name: stickerName), label: "Choose Image",
                                    disabled: stickerName.isEmpty || nameError(stickerName) != nil || stickersUsed >= stickerSlots) {
                    stickerName = ""
                    await model.load()
                }
            }
        }
    }
}
