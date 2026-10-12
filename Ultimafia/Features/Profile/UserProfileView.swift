import SwiftUI
import AVKit
#if canImport(WebKit)
import WebKit
#endif

struct UserProfileView: View {
    var userId: String
    var userName: String

    @Environment(AppModel.self) private var app
    @State private var blob: [String: Any] = [:]
    @State private var error: String?
    @State private var loading = true
    @State private var mediaOpen = true
    @State private var browserItem: UMBrowserItem?

    var body: some View {
        ScrollView {
            if loading {
                ProgressView()
                    .tint(UMTheme.blood)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let error {
                Text(error)
                    .foregroundStyle(UMTheme.muted)
                    .padding()
            } else {
                profileBody
            }
        }
        .background(pageBackground)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(UMTheme.card, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if !app.path.isEmpty { app.path.removeLast() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                        app.path.removeAll()
                    }
                )
            }
        }
        .task { await load() }
        .environment(\.openURL, OpenURLAction { url in
            let scheme = (url.scheme ?? "").lowercased()
            guard scheme == "http" || scheme == "https" else { return .systemAction }
            browserItem = UMBrowserItem(url: url)
            return .handled
        })
        .fullScreenCover(item: $browserItem) { item in
            UMInAppBrowser(url: item.url) {
                browserItem = nil
            }
        }
    }

    private var displayName: String {
        let n = string("name")
        if !n.isEmpty { return n }
        return userName.isEmpty ? "Profile" : userName
    }

    private var canonicalId: String {
        let id = string("id")
        return id.isEmpty ? userId : id
    }

    private var settings: [String: Any] {
        blob["settings"] as? [String: Any] ?? [:]
    }

    private var squareAvatar: Bool {
        (settings["avatarShape"] as? String) == "square"
    }

    private var panelColor: Color {
        Color(umHex: settings["backgroundColor"] as? String) ?? UMTheme.card
    }

    private var customOutline: Color? {
        Color(umHex: settings["backgroundColor"] as? String)
    }

    private func outlinedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        // Site: .box-panel has 8px padding + backgroundColor (the frame).
        // Inner .bio / .content fill is --scheme-color, not the custom color.
        content()
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UMTheme.card)
            .padding(8)
            .background(customOutline ?? UMTheme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var pageBackground: some View {
        let repeatMode = (settings["backgroundRepeatMode"] as? String) ?? "checker"
        if bool("profileBackground"), let url = URL(string: "https://ultimafia.com/uploads/\(canonicalId)_profileBackground.webp") {
            AnimatedWebPView(url: url, showsPlaceholder: false)
                .scaledToFill()
                .clipped()
                .opacity(repeatMode == "stretch" ? 1 : 0.55)
                .ignoresSafeArea()
                .background(UMTheme.bg)
        } else {
            UMTheme.bg.ignoresSafeArea()
        }
    }

    private var profileBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            VStack(alignment: .leading, spacing: 12) {
                if !string("bio").isEmpty {
                    outlinedCard {
                        UMMarkdownView(text: string("bio"))
                    }
                }
                if let media = settings["youtube"] as? String, !media.isEmpty {
                    outlinedCard {
                        mediaCard(media)
                    }
                }
                outlinedCard {
                    metaTiles
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            ProfileCommentsView(location: canonicalId)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            bannerImage
            identityBlock
        }
        .padding(8)
        .background(customOutline ?? UMTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.horizontal, 12)
    }

    private var bannerImage: some View {
        Group {
            if bool("banner"), let url = bannerURL {
                AnimatedWebPView(url: url)
                    .scaledToFill()
            } else {
                UMTheme.elevated
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .clipped()
    }

    private var identityBlock: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 6) {
                Color.clear.frame(height: showsFamilyOrLove ? 52 : 36)
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        PlayerNameView(player: namePlayer, fontSize: 20)
                        ForEach(nameBadges, id: \.self) { name in
                            Text(name)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(UMTheme.blood.opacity(0.35), in: Capsule())
                        }
                    }
                    if !string("pronouns").isEmpty {
                        Text(string("pronouns"))
                            .font(.caption)
                            .foregroundStyle(UMTheme.muted)
                    }
                    if let joined = joinDate {
                        Text("Joined \(joined)")
                            .font(.caption)
                            .foregroundStyle(UMTheme.muted)
                    }
                    if let status = blob["status"] as? String, !status.isEmpty {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(status == "online" ? Color.green : UMTheme.muted)
                                .frame(width: 8, height: 8)
                            Text(status.capitalized)
                                .font(.caption)
                                .foregroundStyle(UMTheme.muted)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
            }
            HStack(alignment: .top, spacing: 6) {
                familyCell
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 72)
                loveCell
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            UMAvatarView(
                userId: canonicalId,
                hasAvatar: bool("avatar"),
                name: displayName,
                size: 64,
                square: squareAvatar
            )
            .overlay {
                Circle().stroke(UMTheme.card, lineWidth: 3).opacity(squareAvatar ? 0 : 1)
            }
            .offset(y: -32)
        }
        .background(UMTheme.card)
    }

    private var showsFamilyOrLove: Bool {
        if blob["family"] is [String: Any] { return true }
        let love = blob["love"] as? [String: Any] ?? [:]
        let loveId = umDictString(love, "id")
        let isLove = bool("isLove") || umDictBool(blob, "isLove")
        let isMarried = bool("isMarried") || umDictBool(blob, "isMarried")
        return !loveId.isEmpty && (isLove || isMarried)
    }

    private var namePlayer: GamePlayer {
        GamePlayer(
            id: canonicalId,
            name: displayName,
            userId: canonicalId,
            avatar: bool("avatar"),
            nameColorHex: umColorString(settings["nameColor"]),
            nameFont: settings["nameFont"] as? String,
            animatedNameColor: settings["animatedNameColor"] as? String,
            nameGradientColorA: umColorString(settings["nameGradientColorA"]),
            nameGradientColorB: umColorString(settings["nameGradientColorB"]),
            nameGradientColorC: umColorString(settings["nameGradientColorC"])
        )
    }

    @ViewBuilder
    private var familyCell: some View {
        if let fam = blob["family"] as? [String: Any] {
            let id = umDictString(fam, "id")
            let name = umDictString(fam, "name")
            let has = umDictBool(fam, "avatar")
            VStack(alignment: .leading, spacing: 4) {
                Text("Member of")
                    .font(.caption.italic())
                    .foregroundStyle(UMTheme.muted)
                HStack(spacing: 6) {
                    if has, !id.isEmpty, let url = URL(string: "https://ultimafia.com/uploads/\(id)_family_avatar.webp") {
                        AnimatedWebPView(url: url, showsPlaceholder: false)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var loveCell: some View {
        let love = blob["love"] as? [String: Any] ?? [:]
        let loveId = umDictString(love, "id")
        let isLove = bool("isLove") || umDictBool(blob, "isLove")
        let isMarried = bool("isMarried") || umDictBool(blob, "isMarried")
        if !loveId.isEmpty, isLove || isMarried {
            let title: String = {
                switch umDictString(love, "type") {
                case "Married": return "Married To"
                default: return "In Love With"
                }
            }()
            let name = umDictString(love, "name")
            Button {
                app.path.append(.profile(id: loveId, name: name))
            } label: {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(title)
                        .font(.caption.italic())
                        .foregroundStyle(UMTheme.muted)
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                        UMAvatarView(
                            userId: loveId,
                            hasAvatar: umDictBool(love, "avatar"),
                            name: name,
                            size: 32
                        )
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var metaTiles: some View {
        HStack(spacing: 10) {
            tile("Kudos", number("kudos"))
            tile("Karma", number("karma"))
            if showsGamesTile {
                tile("Games", mafiaGamesTotal)
            }
        }
    }

    private var showsGamesTile: Bool {
        blob["stats"] != nil
    }

    private func tile(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(UMTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(UMTheme.elevated, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func mediaCard(_ raw: String) -> some View {
        let autoplay = settings["autoplay"] as? Bool ?? false
        let collapsedDefault = settings["collapseMedia"] as? Bool ?? false
        VStack(alignment: .leading, spacing: 8) {
            Button {
                mediaOpen.toggle()
            } label: {
                HStack {
                    Image(systemName: "music.note")
                    Text("Media")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: mediaOpen ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(UMTheme.muted)
                }
            }
            .buttonStyle(.plain)
            // Keep the player mounted when collapsed (desktop CSS-hides it).
            ProfileMediaEmbed(raw: raw, autoplay: autoplay)
                .frame(height: mediaOpen ? 200 : 0)
                .opacity(mediaOpen ? 1 : 0)
                .clipped()
                .allowsHitTesting(mediaOpen)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .onAppear { mediaOpen = !collapsedDefault }
    }

    private var bannerURL: URL? {
        let ext = (blob["bannerExt"] as? String)?.lowercased() ?? "webp"
        let safe = ["webp", "gif", "png", "jpg", "jpeg"].contains(ext) ? ext : "webp"
        return URL(string: "https://ultimafia.com/uploads/\(canonicalId)_banner.\(safe)")
    }

    private var groupNames: [String] {
        let groups = blob["groups"] as? [[String: Any]] ?? []
        return groups.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
    }

    private var nameBadges: [String] {
        groupNames.filter { name in
            let l = name.lowercased()
            if l.contains("ranked") || l.contains("competitive") { return false }
            return true
        }
    }

    private var joinDate: String? {
        let raw = blob["joined"]
        let ms: Double?
        if let n = raw as? Double { ms = n }
        else if let n = raw as? Int { ms = Double(n) }
        else if let n = raw as? NSNumber { ms = n.doubleValue }
        else { ms = nil }
        guard let ms else { return nil }
        let sec = ms > 10_000_000_000 ? ms / 1000 : ms
        let date = Date(timeIntervalSince1970: sec)
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func string(_ key: String) -> String {
        if let s = blob[key] as? String { return s }
        return ""
    }

    private func bool(_ key: String) -> Bool {
        if let b = blob[key] as? Bool { return b }
        if let n = blob[key] as? NSNumber { return n.boolValue }
        if let s = blob[key] as? String { return s == "true" || s == "1" }
        return false
    }

    private func number(_ key: String) -> Int {
        umStatInt(blob[key])
    }

    /// Ranked+competitive (`stats.Mafia.all`) + unranked. Matches desktop All Games.
    /// `stats` is omitted when hideStatistics is on.
    private var mafiaGamesTotal: Int {
        guard let stats = blob["stats"] as? [String: Any],
              let mafia = stats["Mafia"] as? [String: Any] else { return 0 }
        return umGetTotalGames(mafia["all"]) + umGetTotalGames(mafia["unranked"])
    }

    private func load() async {
        loading = true
        error = nil
        do {
            blob = try await APIClient.shared.userProfile(userId)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private let umLinkBlue = Color(red: 104 / 255, green: 169 / 255, blue: 220 / 255)

private func umStatInt(_ any: Any?) -> Int {
    if let n = any as? Int { return n }
    if let n = any as? Double { return Int(n) }
    if let n = any as? NSNumber { return n.intValue }
    return 0
}

/// Same as react_main/src/utils/mafiaStats.js getTotalGames.
private func umGetTotalGames(_ any: Any?) -> Int {
    guard let stats = any as? [String: Any] else { return 0 }
    let wins = stats["wins"] as? [String: Any] ?? [:]
    let abandons = stats["abandons"] as? [String: Any] ?? [:]
    let winsCount = max(0, umStatInt(wins["count"]))
    let winsTotalRaw = max(winsCount, umStatInt(wins["total"]))
    let abandonCount = max(0, umStatInt(abandons["count"]))
    let totalGamesField = max(0, umStatInt(stats["totalGames"]))
    var completed = winsTotalRaw
    if abandonCount > 0, totalGamesField > 0, totalGamesField <= winsTotalRaw {
        completed = max(winsCount, winsTotalRaw - abandonCount)
    }
    return completed + abandonCount
}


struct UMMarkdownView: View {
    var text: String
    /// When set, role names render like in-game chat mentions (yellow + icon, tap for details).
    var roleGameType: String? = nil
    var otherRoles: [String] = []

    @State private var selectedRole: UMRoleMentionItem?

    var body: some View {
        if roleGameType != nil {
            content
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == UMRoleMentionItem.scheme else { return .systemAction }
                    let name = url.host(percentEncoded: false) ?? url.path(percentEncoded: false)
                    selectedRole = UMRoleMentionItem(name: name.removingPercentEncoding ?? name)
                    return .handled
                })
                .sheet(item: $selectedRole) { item in
                    RoleDetailsSheet(roleRaw: item.name, gameType: roleGameType ?? "Mafia", otherRoles: otherRoles)
                }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                switch chunk {
                case .text(let s):
                    textBlocks(s)
                case .image(let url, let link):
                    Group {
                        if let link {
                            Link(destination: link) {
                                imageView(url)
                            }
                        } else {
                            imageView(url)
                        }
                    }
                }
            }
        }
    }

    private enum Chunk {
        case text(String)
        case image(URL, link: URL?)
    }

    private enum Block {
        case heading(Int, String)
        case listItem(String)
        case paragraph(String)
    }

    @ViewBuilder
    private func textBlocks(_ raw: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks(from: raw).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let t):
                    richLine(t, headingLevel: level)
                case .listItem(let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.white)
                        richLine(t, headingLevel: nil)
                    }
                case .paragraph(let t):
                    richLine(t, headingLevel: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func imageView(_ url: URL) -> some View {
        AnimatedWebPView(url: url)
            .scaledToFit()
            .frame(maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var chunks: [Chunk] {
        let linked = try? NSRegularExpression(pattern: #"\[!\[([^\]]*)\]\(([^)]+)\)\]\(([^)]+)\)"#)
        let bare = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#)
        guard let linked, let bare else { return [.text(text)] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var marks: [(NSRange, Chunk)] = []
        for match in linked.matches(in: text, range: full) {
            let imgStr = ns.substring(with: match.range(at: 2))
            let hrefStr = ns.substring(with: match.range(at: 3))
            if let img = absoluteUpload(imgStr) {
                marks.append((match.range, .image(img, link: absoluteUpload(hrefStr))))
            }
        }
        for match in bare.matches(in: text, range: full) {
            if marks.contains(where: { NSIntersectionRange($0.0, match.range).length > 0 }) { continue }
            let imgStr = ns.substring(with: match.range(at: 2))
            if let img = absoluteUpload(imgStr) {
                marks.append((match.range, .image(img, link: nil)))
            }
        }
        marks.sort { $0.0.location < $1.0.location }
        var out: [Chunk] = []
        var cursor = 0
        for (range, chunk) in marks {
            if range.location > cursor {
                let raw = ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
                if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    out.append(.text(raw))
                }
            }
            out.append(chunk)
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            let raw = ns.substring(from: cursor)
            if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(.text(raw))
            }
        }
        return out.isEmpty ? [.text(text)] : out
    }

    private func blocks(from raw: String) -> [Block] {
        let cleaned = preprocess(raw)
        let lines = cleaned.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [Block] = []
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                i += 1
                continue
            }
            if let heading = parseHeading(trimmed) {
                out.append(.heading(heading.0, heading.1))
                i += 1
                continue
            }
            if let item = parseListItem(trimmed) {
                out.append(.listItem(item))
                i += 1
                continue
            }
            var parts = [trimmed]
            i += 1
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if parseHeading(t) != nil || parseListItem(t) != nil { break }
                parts.append(t)
                i += 1
            }
            out.append(.paragraph(parts.joined(separator: " ")))
        }
        return out
    }

    private func parseHeading(_ s: String) -> (Int, String)? {
        guard s.hasPrefix("#") else { return nil }
        var n = 0
        for ch in s {
            if ch == "#" { n += 1 } else { break }
        }
        guard n >= 1, n <= 6, n < s.count else { return nil }
        let rest = s.dropFirst(n)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return (n, rest.trimmingCharacters(in: .whitespaces))
    }

    private func parseListItem(_ s: String) -> String? {
        for prefix in ["- ", "* ", "+ "] {
            if s.hasPrefix(prefix) {
                return String(s.dropFirst(prefix.count))
            }
        }
        var i = s.startIndex
        var sawDigit = false
        while i < s.endIndex, s[i].isNumber {
            sawDigit = true
            i = s.index(after: i)
        }
        guard sawDigit, i < s.endIndex, s[i] == "." else { return nil }
        let after = s.index(after: i)
        guard after < s.endIndex, s[after] == " " else { return nil }
        return String(s[s.index(after: after)...])
    }

    @ViewBuilder
    private func richLine(_ s: String, headingLevel: Int?) -> some View {
        let parts = umEmoteParts(s)
        if parts.contains(where: { if case .emote = $0 { return true }; return false }) {
            UMFlowLayout(spacing: 4) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .text(let t):
                        Text(styledInline(t, headingLevel: headingLevel))
                    case .emote(let info):
                        AnimatedWebPView(url: info.url, showsPlaceholder: false)
                            .frame(width: 22, height: 22)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let type = roleGameType {
            umRoleMentionText(styledInline(s, headingLevel: headingLevel), gameType: type)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(styledInline(s, headingLevel: headingLevel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func styledInline(_ s: String, headingLevel: Int?) -> AttributedString {
        if let level = headingLevel {
            return headingMarkdown(s, level: level)
        }
        return inlineMarkdown(s)
    }

    private func headingMarkdown(_ s: String, level: Int) -> AttributedString {
        var attr = inlineMarkdown(s)
        let size: CGFloat
        switch level {
        case 1: size = 28
        case 2: size = 22
        case 3: size = 20
        case 4: size = 17
        default: size = 15
        }
        let font = Font.system(size: size, weight: .bold)
        let runs = Array(attr.runs)
        for run in runs {
            attr[run.range].font = font
        }
        return attr
    }

    private func inlineMarkdown(_ s: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        let parsed: AttributedString
        if let attr = try? AttributedString(markdown: s, options: options) {
            parsed = attr
        } else {
            parsed = AttributedString(s)
        }
        return paint(parsed)
    }

    private func preprocess(_ s: String) -> String {
        var t = s
        t = umRegexReplace(t, #"\{color:[^}]+\}(.+?)\{\/color\}"#, "$1")
        t = umRegexReplace(t, #"\{size:[^}]+\}(.+?)\{\/size\}"#, "$1")
        t = umRegexReplace(t, #"\{center\}(.+?)\{\/center\}"#, "$1")
        t = umRegexReplace(t, #"\{color:[^}]*\}"#, "")
        t = umRegexReplace(t, #"\{size:[^}]*\}"#, "")
        t = umRegexReplace(t, #"\{center\}"#, "")
        t = umRegexReplace(t, #"\{\/color\}"#, "")
        t = umRegexReplace(t, #"\{\/size\}"#, "")
        t = umRegexReplace(t, #"\{\/center\}"#, "")
        t = t.replacingOccurrences(of: "||", with: "")
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        return t
    }

    private func paint(_ source: AttributedString) -> AttributedString {
        var out = source
        let runs = Array(out.runs)
        for run in runs {
            let range = run.range
            if let url = run.link {
                out[range].link = resolveUMURL(url)
                out[range].foregroundColor = umLinkBlue
                out[range].underlineStyle = .single
            } else if out[range].foregroundColor == nil {
                out[range].foregroundColor = .white
            }
        }
        return out
    }

    private func resolveUMURL(_ url: URL) -> URL {
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return url
        }
        let base = URL(string: "https://ultimafia.com/")!
        if let abs = URL(string: url.relativeString, relativeTo: base)?.absoluteURL {
            return abs
        }
        return url
    }

    private func absoluteUpload(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return URL(string: s) }
        if s.hasPrefix("/") { return URL(string: "https://ultimafia.com" + s) }
        return URL(string: "https://ultimafia.com/" + s)
    }
}

private func umRegexReplace(_ source: String, _ pattern: String, _ template: String) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return source
    }
    let range = NSRange(source.startIndex..., in: source)
    return re.stringByReplacingMatches(in: source, options: [], range: range, withTemplate: template)
}

private func umDictInt(_ obj: [String: Any], _ key: String) -> Int {
    if let n = obj[key] as? Int { return n }
    if let n = obj[key] as? Double { return Int(n) }
    if let n = obj[key] as? NSNumber { return n.intValue }
    if let s = obj[key] as? String, let n = Int(s) { return n }
    return 0
}

private func umDictBool(_ obj: [String: Any], _ key: String) -> Bool {
    if let b = obj[key] as? Bool { return b }
    if let n = obj[key] as? NSNumber { return n.boolValue }
    if let s = obj[key] as? String { return s == "true" || s == "1" }
    return false
}

private func umDictString(_ obj: [String: Any], _ key: String) -> String {
    if let s = obj[key] as? String { return s }
    if let n = obj[key] as? NSNumber { return n.stringValue }
    return ""
}

private func umCommentId(_ comment: [String: Any]) -> String {
    umDictString(comment, "id")
}

struct ProfileCommentsView: View {
    var location: String
    @Environment(AppModel.self) private var app

    @State private var comments: [[String: Any]] = []
    @State private var page = 1
    @State private var maxPage = 1
    @State private var loading = true
    @State private var draft = ""
    @State private var error: String?
    @State private var posting = false

    private let emotes = ["👍", "😂", "❤️", "🔥", "💀", "👀", "🎉", "😢"]
    private let siteReact = [":)", ":(", "<3", ":star:", ":fufu:", ":doge:", ":bump:", ":rawr:", ":zzz:"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline)
                .foregroundStyle(.white)
            if loading {
                ProgressView()
                    .tint(UMTheme.blood)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if comments.isEmpty {
                Text("No comments yet.")
                    .font(.subheadline)
                    .foregroundStyle(UMTheme.muted)
            } else {
                ForEach(Array(comments.enumerated()), id: \.offset) { index, comment in
                    commentCard(comment, index: index)
                }
            }
            if !loading, maxPage > 1 {
                HStack {
                    Button("Prev") {
                        Task { await load(page: page - 1) }
                    }
                    .disabled(page <= 1)
                    Spacer()
                    Text("Page \(page) of \(maxPage)")
                        .font(.caption)
                        .foregroundStyle(UMTheme.muted)
                    Spacer()
                    Button("Next") {
                        Task { await load(page: page + 1) }
                    }
                    .disabled(page >= maxPage)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(UMTheme.blood)
            }
            if app.isSignedIn {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Write a comment", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .padding(8)
                        .background(UMTheme.elevated, in: RoundedRectangle(cornerRadius: 8))
                    Button("Post") {
                        Task { await post() }
                    }
                    .disabled(posting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(UMTheme.blood)
                    .font(.subheadline.weight(.semibold))
                }
            } else {
                Text("Sign in to comment.")
                    .font(.caption)
                    .foregroundStyle(UMTheme.muted)
            }
        }
        .task(id: location) { await load(page: 1) }
    }

    private func commentCard(_ comment: [String: Any], index: Int) -> some View {
        let author = comment["author"] as? [String: Any] ?? [:]
        let authorId = umDictString(author, "id")
        let vanity = umDictString(author, "vanityUrl")
        let authorName = {
            let n = umDictString(author, "name")
            return n.isEmpty ? "[deleted]" : n
        }()
        let navId = vanity.isEmpty ? authorId : vanity
        let vote = umDictInt(comment, "vote")
        let voteCount = umDictInt(comment, "voteCount")
        let deleted = umDictBool(comment, "deleted")
        let reactions = (comment["reactions"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Button {
                    Task { await voteComment(index: index, direction: 1) }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(vote == 1 ? UMTheme.blood : UMTheme.muted)
                }
                .buttonStyle(.plain)
                Text("\(voteCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(vote == 1 ? UMTheme.blood : (vote == -1 ? UMTheme.muted : .white))
                Button {
                    Task { await voteComment(index: index, direction: -1) }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(vote == -1 ? UMTheme.muted : Color.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    UMAvatarView(
                        userId: authorId.isEmpty ? nil : authorId,
                        hasAvatar: umDictBool(author, "avatar"),
                        name: authorName,
                        size: 28
                    )
                    Button(authorName) {
                        if !navId.isEmpty {
                            app.path.append(.profile(id: navId, name: authorName))
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    if let ago = relativeTime(comment["date"]) {
                        Text(ago)
                            .font(.caption)
                            .foregroundStyle(UMTheme.muted)
                    }
                }
                if deleted {
                    UMMarkdownView(text: "*deleted*")
                } else {
                    UMMarkdownView(text: umDictString(comment, "content"))
                }
                HStack(spacing: 6) {
                    ForEach(Array(reactions.enumerated()), id: \.offset) { _, row in
                        let emote = umDictString(row, "emote")
                        let count = umDictInt(row, "count")
                        let mine = umDictBool(row, "mine")
                        Button {
                            Task { await react(index: index, emote: emote, kind: umDictString(row, "emoteKind"), path: umDictString(row, "emotePath")) }
                        } label: {
                            HStack(spacing: 4) {
                                UMEmoteView(token: emote, kind: umDictString(row, "emoteKind"), path: umDictString(row, "emotePath"), size: 16)
                                Text("\(count)")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(mine ? UMTheme.blood.opacity(0.35) : UMTheme.elevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Menu {
                        ForEach(emotes, id: \.self) { emote in
                            Button(emote) {
                                Task { await react(index: index, emote: emote, kind: "unicode") }
                            }
                        }
                        Divider()
                        ForEach(siteReact, id: \.self) { emote in
                            Button(emote) {
                                Task { await react(index: index, emote: emote, kind: "site") }
                            }
                        }
                    } label: {
                        Text("+")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(UMTheme.muted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(UMTheme.elevated, in: Capsule())
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func load(page newPage: Int) async {
        let target = max(1, newPage)
        if comments.isEmpty { loading = true }
        error = nil
        do {
            let result = try await APIClient.shared.comments(location: location, page: target)
            comments = result.comments
            maxPage = result.maxPage
            page = result.page
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func post() async {
        let text = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !text.isEmpty else { return }
        posting = true
        error = nil
        do {
            try await APIClient.shared.postComment(content: text, location: location)
            draft = ""
            await load(page: 1)
        } catch {
            self.error = error.localizedDescription
        }
        posting = false
    }

    private func voteComment(index: Int, direction: Int) async {
        guard comments.indices.contains(index) else { return }
        let id = umCommentId(comments[index])
        guard !id.isEmpty else { return }
        let old = umDictInt(comments[index], "vote")
        do {
            let newVote = try await APIClient.shared.voteItem(item: id, itemType: "comment", direction: direction)
            guard let idx = comments.firstIndex(where: { umCommentId($0) == id }) else { return }
            var row = comments[idx]
            var count = umDictInt(row, "voteCount")
            if old == 0 {
                count += direction
            } else if old == direction {
                count -= direction
            } else {
                count += 2 * direction
            }
            row["vote"] = newVote
            row["voteCount"] = count
            comments[idx] = row
        } catch {}
    }

    private func react(index: Int, emote: String, kind: String = "", path: String = "") async {
        guard comments.indices.contains(index) else { return }
        let id = umCommentId(comments[index])
        guard !id.isEmpty, !emote.isEmpty else { return }
        let resolvedKind: String = {
            if !kind.isEmpty { return kind }
            if UMEmotes.info(for: emote) != nil { return "site" }
            return "unicode"
        }()
        do {
            let reactions = try await APIClient.shared.reactItem(item: id, itemType: "comment", emote: emote, emoteKind: resolvedKind, emotePath: path)
            guard let idx = comments.firstIndex(where: { umCommentId($0) == id }) else { return }
            var row = comments[idx]
            row["reactions"] = reactions
            comments[idx] = row
        } catch {}
    }

    private func relativeTime(_ raw: Any?) -> String? {
        let ms: Double?
        if let n = raw as? Double { ms = n }
        else if let n = raw as? Int { ms = Double(n) }
        else if let n = raw as? NSNumber { ms = n.doubleValue }
        else if let s = raw as? String, let n = Double(s) { ms = n }
        else { ms = nil }
        guard let ms, ms > 0 else { return nil }
        let sec = ms > 10_000_000_000 ? ms / 1000 : ms
        let elapsed = max(0, Int(Date().timeIntervalSince(Date(timeIntervalSince1970: sec))))
        if elapsed < 60 { return "\(max(elapsed, 1))s ago" }
        let m = elapsed / 60
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        if h < 24 { return "\(h)h ago" }
        let d = h / 24
        if d < 7 { return "\(d)d ago" }
        let w = d / 7
        if w < 52 { return "\(w)w ago" }
        return "\(d / 365)y ago"
    }
}

private struct ProfileMediaEmbed: View {
    var raw: String
    var autoplay: Bool

    var body: some View {
        if let id = youtubeId(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            #if canImport(WebKit)
            ProfileWebEmbed(html: youtubeHTML(id: id, autoplay: autoplay))
            #else
            if let url = URL(string: "https://www.youtube.com/embed/\(id)") {
                Link(url.absoluteString, destination: url)
            }
            #endif
        } else if let url = embedURL {
            #if canImport(WebKit)
            ProfileWebEmbed(url: url)
            #else
            Link(url.absoluteString, destination: url)
            #endif
        } else if let url = URL(string: raw), isDirect(url) {
            ProfileAudioBar(url: url)
        } else if let url = URL(string: raw) {
            Link("Open media", destination: url)
                .foregroundStyle(UMTheme.blood)
        }
    }

    private var embedURL: URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("open.spotify.com"), let u = URL(string: s.replacingOccurrences(of: "/track/", with: "/embed/track/").replacingOccurrences(of: "/album/", with: "/embed/album/").replacingOccurrences(of: "/playlist/", with: "/embed/playlist/")) {
            return u
        }
        if s.contains("soundcloud.com") {
            let enc = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
            return URL(string: "https://w.soundcloud.com/player/?url=\(enc)&visual=true")
        }
        if s.contains("vimeo.com") {
            let id = s.split(separator: "/").last.map(String.init) ?? ""
            if !id.isEmpty { return URL(string: "https://player.vimeo.com/video/\(id)?playsinline=1") }
        }
        return nil
    }

    private func isDirect(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp3", "ogg", "wav", "m4a", "mp4", "webm"].contains(ext)
    }

    private func youtubeId(_ s: String) -> String? {
        let patterns = [
            #"youtu\.be/([A-Za-z0-9_-]{6,})"#,
            #"[?&]v=([A-Za-z0-9_-]{6,})"#,
            #"youtube\.com/embed/([A-Za-z0-9_-]{6,})"#,
            #"youtube\.com/shorts/([A-Za-z0-9_-]{6,})"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p),
               let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let r = Range(m.range(at: 1), in: s) {
                return String(s[r])
            }
        }
        return nil
    }

    private func youtubeHTML(id: String, autoplay: Bool) -> String {
        // Desktop: autoplay=0|1 and mute=0. iOS often still starts muted; unmuted autoplay is not reliable.
        var src = "https://www.youtube.com/embed/\(id)?playsinline=1&rel=0&modestbranding=1&origin=https://ultimafia.com"
        src += "&autoplay=\(autoplay ? 1 : 0)&mute=0"
        return """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="\(src)"
          referrerpolicy="origin"
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
          allowfullscreen></iframe>
        </body></html>
        """
    }
}

private struct ProfileAudioBar: View {
    var url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player = AVPlayer(url: url)
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }
}

#if canImport(WebKit)
private struct ProfileWebEmbed: UIViewRepresentable {
    var html: String? = nil
    var url: URL? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        load(into: web, context: context)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        load(into: web, context: context)
    }

    private func load(into web: WKWebView, context: Context) {
        if let html {
            guard context.coordinator.lastHTML != html else { return }
            context.coordinator.lastHTML = html
            context.coordinator.lastURL = nil
            web.loadHTMLString(html, baseURL: URL(string: "https://ultimafia.com/"))
        } else if let url {
            guard context.coordinator.lastURL != url else { return }
            context.coordinator.lastURL = url
            context.coordinator.lastHTML = nil
            var req = URLRequest(url: url)
            req.setValue("https://ultimafia.com/", forHTTPHeaderField: "Referer")
            web.load(req)
        }
    }

    final class Coordinator {
        var lastHTML: String?
        var lastURL: URL?
    }
}
#endif
