import SwiftUI

/// Family page, mirroring react_main/src/pages/User/Family.jsx.
/// Live data: GET /api/family/:familyId/profile (routes/family.js). Comments use location "family/<id>".
/// Layout (per Vinman): hero, members grid (3/row), description, music, trophies, comments + add box.
struct FamilyView: View {
    var familyId: String
    var familyName: String

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
                UMLoadErrorView(title: "Couldn't load family.", detail: error) {
                    Task { await load() }
                }
            } else {
                familyBody
            }
        }
        .background(pageBackground)
        .navigationTitle("")
        .umInlineTitle()
        .navigationBarBackButtonHidden(true)
        .umNavigationBar(.hidden)
        .task { await load() }
        .environment(\.openURL, OpenURLAction { url in
            let scheme = (url.scheme ?? "").lowercased()
            guard scheme == "http" || scheme == "https" else { return .systemAction }
            browserItem = UMBrowserItem(url: url)
            return .handled
        })
        .umFullScreenCover(item: $browserItem) { item in
            UMInAppBrowser(url: item.url) { browserItem = nil }
        }
    }

    // MARK: Data helpers

    private var canonicalId: String { str(blob, "id").isEmpty ? familyId : str(blob, "id") }
    private var displayName: String {
        let n = str(blob, "name")
        return n.isEmpty ? (familyName.isEmpty ? "Family" : familyName) : n
    }
    /// Family.jsx: stable sort of the server's member order (join order) by role rank
    /// leader 0, officer 1, member/unknown 2.
    private var members: [[String: Any]] {
        let raw = blob["members"] as? [[String: Any]] ?? []
        let rank = ["leader": 0, "officer": 1, "member": 2]
        return raw.enumerated().sorted { a, b in
            let ra = rank[str(a.element, "role")] ?? 2, rb = rank[str(b.element, "role")] ?? 2
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    private func str(_ o: [String: Any], _ k: String) -> String {
        if let s = o[k] as? String { return s }
        if let n = o[k] as? NSNumber { return n.stringValue }
        return ""
    }
    private func flag(_ o: [String: Any], _ k: String) -> Bool {
        if let b = o[k] as? Bool { return b }
        if let n = o[k] as? NSNumber { return n.boolValue }
        return false
    }
    private func int(_ o: [String: Any], _ k: String) -> Int {
        if let n = o[k] as? Int { return n }
        if let n = o[k] as? Double { return Int(n) }
        if let n = o[k] as? NSNumber { return n.intValue }
        return 0
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UMTheme.card)
            .padding(8)
            .background(UMTheme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var pageBackground: some View {
        let mode = str(blob, "backgroundRepeatMode")
        if flag(blob, "background"),
           let url = URL(string: "\(UMConfig.site)/uploads/\(canonicalId)_familyBackground.webp") {
            AnimatedWebPView(url: url, showsPlaceholder: false)
                .scaledToFill()
                .clipped()
                .opacity(mode == "stretch" ? 1 : 0.55)
                .ignoresSafeArea()
                .background(UMTheme.bg)
        } else {
            UMTheme.bg.ignoresSafeArea()
        }
    }

    // MARK: Layout

    private var familyBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            VStack(alignment: .leading, spacing: 12) {
                card { membersGrid }
                if !str(blob, "bio").isEmpty {
                    card { UMMarkdownView(text: str(blob, "bio")) }
                }
                if !str(blob, "mediaUrl").isEmpty {
                    card { mediaCard(str(blob, "mediaUrl")) }
                }
                let trophies = UMTrophy.list(from: blob)
                if !trophies.isEmpty {
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Trophies (\(trophies.count))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            UMTrophyRow(trophies: trophies)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            ProfileCommentsView(location: "family/\(canonicalId)")
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            bannerImage
            ZStack(alignment: .top) {
                VStack(spacing: 4) {
                    Color.clear.frame(height: 40)
                    Text(displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if let founded = foundedText {
                        Text("Founded \(founded)")
                            .font(.caption)
                            .foregroundStyle(UMTheme.muted)
                    }
                    statsLine
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
                familyAvatar
                    .offset(y: -32)
            }
            .background(UMTheme.card)
        }
        .padding(8)
        .background(UMTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.horizontal, 12)
    }

    private var bannerImage: some View {
        Group {
            if flag(blob, "banner"), let url = bannerURL {
                AnimatedWebPView(url: url).scaledToFill()
            } else {
                UMTheme.elevated
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .clipped()
    }

    private var bannerURL: URL? {
        let ext = str(blob, "bannerExt").lowercased()
        let safe = ["webp", "gif", "png", "jpg", "jpeg"].contains(ext) ? ext : "webp"
        return URL(string: "\(UMConfig.site)/uploads/\(canonicalId)_family_banner.\(safe)")
    }

    @ViewBuilder
    private var familyAvatar: some View {
        Group {
            if flag(blob, "avatar"),
               let url = URL(string: "\(UMConfig.site)/uploads/\(canonicalId)_family_avatar.webp") {
                AnimatedWebPView(url: url, showsPlaceholder: false)
            } else {
                ZStack {
                    UMTheme.elevated
                    Image(systemName: "person.3.fill").foregroundStyle(UMTheme.muted)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UMTheme.card, lineWidth: 3))
    }

    private var statsLine: some View {
        let limit = int(blob, "memberLimit")
        let count = members.count
        return HStack(spacing: 14) {
            Label(limit > 0 ? "\(count)/\(limit)" : "\(count)", systemImage: "person.2.fill")
            Label("\(int(blob, "treasury"))", systemImage: "dollarsign.circle")
            if blob["applicationsOpen"] != nil {
                Label(flag(blob, "applicationsOpen") ? "Open" : "Closed",
                      systemImage: flag(blob, "applicationsOpen") ? "door.left.hand.open" : "lock.fill")
            }
        }
        .font(.caption)
        .foregroundStyle(UMTheme.muted)
        .padding(.top, 2)
    }

    private var foundedText: String? {
        guard let raw = blob["createdAt"] else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date: Date?
        if let s = raw as? String { date = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) }
        else if let n = raw as? Double { date = Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
        return date?.formatted(date: .abbreviated, time: .omitted)
    }

    private var membersGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Members")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3),
                      spacing: 14) {
                ForEach(members.indices, id: \.self) { i in
                    memberCell(members[i])
                }
            }
        }
    }

    private func memberCell(_ m: [String: Any]) -> some View {
        let id = str(m, "id")
        let name = str(m, "name")
        let vanity = str(m, "vanityUrl")
        let role = memberRole(m)
        return Button {
            guard !id.isEmpty else { return }
            app.openProfile(id: vanity.isEmpty ? id : vanity, name: name)
        } label: {
            VStack(spacing: 4) {
                UMAvatarView(userId: id, hasAvatar: flag(m, "avatar"), name: name, size: 52)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(role)
                    .font(.caption2)
                    .foregroundStyle(role == "Member" ? UMTheme.muted : UMTheme.blood)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(role)")
    }

    /// Site roles: leader / officer / member, plus founder flag.
    private func memberRole(_ m: [String: Any]) -> String {
        if flag(m, "isLeader") || str(m, "role") == "leader" {
            return flag(m, "isFounder") ? "Founder · Leader" : "Leader"
        }
        if flag(m, "isFounder") { return "Founder" }
        let r = str(m, "role")
        return r.isEmpty ? "Member" : r.prefix(1).uppercased() + r.dropFirst()
    }

    @ViewBuilder
    private func mediaCard(_ raw: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { mediaOpen.toggle() } label: {
                HStack {
                    Image(systemName: "music.note")
                    Text("Media").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: mediaOpen ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(UMTheme.muted)
                }
            }
            .buttonStyle(.plain)
            ProfileMediaEmbed(raw: raw, autoplay: flag(blob, "mediaAutoplay"))
                .frame(height: mediaOpen ? 200 : 0)
                .opacity(mediaOpen ? 1 : 0)
                .clipped()
                .allowsHitTesting(mediaOpen)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .onAppear { mediaOpen = !flag(blob, "mediaCollapse") }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            blob = try await APIClient.shared.familyProfile(familyId)
        } catch {
            self.error = UMFriendlyError.message(for: error)
        }
        loading = false
    }
}
