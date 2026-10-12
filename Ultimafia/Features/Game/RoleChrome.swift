import SwiftUI

enum RoleGuess: Hashable, Codable {
    case unknown
    case maybe(String)
    case sure(String)

    var roleKey: String? {
        switch self {
        case .unknown: return nil
        case .maybe(let r), .sure(let r): return r
        }
    }

    var isUncertain: Bool {
        if case .maybe = self { return true }
        return false
    }
}

struct RoleMarkSnapshot: Codable {
    var guesses: [String: RoleGuess] = [:]
    var known: [String: String] = [:]
    var teammates: [String] = []
    var selfRoleName: String?
    var selfRoleCategory: String?
    var selfRoleModifiers: [String] = []
}

enum RoleMarkStore {
    private static func key(_ gameId: String) -> String { "um.roleMarks.\(gameId)" }

    static func load(gameId: String) -> RoleMarkSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key(gameId)) else { return nil }
        return try? JSONDecoder().decode(RoleMarkSnapshot.self, from: data)
    }

    static func save(gameId: String, snapshot: RoleMarkSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key(gameId))
    }

    static func clear(gameId: String) {
        UserDefaults.standard.removeObject(forKey: key(gameId))
    }
}

struct SetupRole: Identifiable, Hashable {
    var id: String { raw }
    var raw: String
    var count: Int

    var name: String { raw.split(separator: ":").first.map(String.init) ?? raw }

    var modifiers: [String] {
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count > 1 else { return [] }
        return parts[1].split(separator: "/").map(String.init).filter { !$0.isEmpty }
    }
}


enum SetupRoleParse {
    struct Bundle {
        var rolesets: [[SetupRole]]
        var banished: [SetupRole]
    }

    static func parse(
        rolesBlob: Any?,
        closed: Bool,
        useRoleGroups: Bool,
        count: [String: Any]?,
        gameType: String
    ) -> Bundle {
        func countVal(_ val: Any) -> Int {
            if let i = val as? Int { return i }
            if let d = val as? Double { return Int(d) }
            if let n = val as? NSNumber { return n.intValue }
            return 1
        }
        func isEvent(_ key: String) -> Bool {
            let name = key.split(separator: ":").first.map(String.init) ?? key
            if name.lowercased() == "event" { return true }
            if let align = RoleCatalog.shared.alignment(of: name, gameType: gameType),
               align.caseInsensitiveCompare("Event") == .orderedSame {
                return true
            }
            return false
        }
        func isBanished(_ key: String) -> Bool {
            let parts = key.split(separator: ":", maxSplits: 1)
            guard parts.count > 1 else { return false }
            return parts[1].split(separator: "/").contains {
                $0.caseInsensitiveCompare("Banished") == .orderedSame
            }
        }
        func rolesFromDict(_ dict: [String: Any], banishedMap: inout [String: Int]) -> [SetupRole] {
            var map: [String: Int] = [:]
            for (k, v) in dict {
                if isEvent(k) { continue }
                let n = countVal(v)
                guard n > 0 else { continue }
                if isBanished(k) {
                    banishedMap[k, default: 0] += n
                    continue
                }
                map[k, default: 0] += n
            }
            return map.map { SetupRole(raw: $0.key, count: $0.value) }
                .sorted { $0.name < $1.name }
        }

        var blob: Any? = rolesBlob
        if let s = blob as? String, let data = s.data(using: .utf8) {
            blob = try? JSONSerialization.jsonObject(with: data)
        }

        var banishedMap: [String: Int] = [:]
        if let arr = blob as? [Any] {
            for item in arr {
                guard let dict = item as? [String: Any] else { continue }
                _ = rolesFromDict(dict, banishedMap: &banishedMap)
            }
        } else if let dict = blob as? [String: Any] {
            _ = rolesFromDict(dict, banishedMap: &banishedMap)
        }
        let banished = banishedMap.map { SetupRole(raw: $0.key, count: $0.value) }
            .sorted { $0.name < $1.name }

        if closed, !useRoleGroups, let count {
            let roles = count.compactMap { key, val -> SetupRole? in
                let n = countVal(val)
                guard n > 0 else { return nil }
                return SetupRole(raw: key, count: n)
            }.sorted { $0.name < $1.name }
            return Bundle(rolesets: [roles], banished: banished)
        }

        var rolesets: [[SetupRole]] = []
        if let arr = blob as? [Any] {
            for item in arr {
                guard let dict = item as? [String: Any] else { continue }
                var unused: [String: Int] = [:]
                rolesets.append(rolesFromDict(dict, banishedMap: &unused))
            }
        } else if let dict = blob as? [String: Any] {
            var unused: [String: Int] = [:]
            rolesets.append(rolesFromDict(dict, banishedMap: &unused))
        }
        if rolesets.isEmpty { rolesets = [[]] }
        return Bundle(rolesets: rolesets, banished: banished)
    }
}

struct RoleIconView: View {
    var role: String
    var gameType: String
    var size: CGFloat = 28

    private var roleName: String {
        role.split(separator: ":").first.map(String.init) ?? role
    }

    private var modifiers: [String] {
        let parts = role.split(separator: ":", maxSplits: 1)
        guard parts.count > 1 else { return [] }
        return parts[1].split(separator: "/").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            roleImage
            modifierBadge
                .offset(x: size * 0.18, y: -size * 0.18)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var roleImage: some View {
        if let url = RoleArt.roleURL(gameType: gameType, name: roleName) {
            AnimatedWebPView(url: url, showsPlaceholder: false)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            fallback
        }
    }

    @ViewBuilder
    private var modifierBadge: some View {
        let mods = modifiers
        let badgeSize = max(10, size * 0.42)
        if mods.count == 1, let url = RoleArt.modifierURL(gameType: gameType, name: mods[0]) {
            AnimatedWebPView(url: url, showsPlaceholder: false)
                .frame(width: badgeSize, height: badgeSize)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        } else if mods.count > 1, let url = RoleArt.badgeURL(modifierCount: mods.count) {
            AnimatedWebPView(url: url, showsPlaceholder: false)
                .frame(width: badgeSize, height: badgeSize)
        }
    }

    private var fallback: some View {
        let letter = String(roleName.prefix(1)).uppercased()
        return ZStack {
            RoundedRectangle(cornerRadius: 4).fill(UMTheme.elevated)
            Text(letter)
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct SetupPreviewStrip: View {
    var gameType: String
    var rolesets: [[SetupRole]]
    var banished: [SetupRole]
    var isSimpleMulti: Bool
    var displayedRoles: [SetupRole]? = nil
    var onCycle: (() -> Void)? = nil
    var compact: Bool = true

    @State private var localIndex = 0
    @State private var selected: SetupRole?
    @State private var showBanished = false

    private var iconSize: CGFloat { compact ? 22 : 24 }

    private var roles: [SetupRole] {
        if let displayedRoles { return displayedRoles }
        guard rolesets.indices.contains(localIndex) else { return rolesets.first ?? [] }
        return rolesets[localIndex]
    }

    private var otherRoles: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for set in rolesets {
            for role in set where seen.insert(role.raw).inserted {
                out.append(role.raw)
            }
        }
        for role in banished where seen.insert(role.raw).inserted {
            out.append(role.raw)
        }
        return out
    }

    var body: some View {
        if !roles.isEmpty || !banished.isEmpty {
            HStack(spacing: compact ? 2 : 4) {
                if isSimpleMulti {
                    Button {
                        if let onCycle {
                            onCycle()
                        } else if !rolesets.isEmpty {
                            localIndex = (localIndex + 1) % rolesets.count
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font((compact ? Font.subheadline : Font.body).weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cycle role sets")
                    .padding(.leading, compact ? 0 : 6)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: compact ? 6 : 8) {
                        ForEach(roles) { role in
                            Button {
                                selected = role
                            } label: {
                                HStack(spacing: 4) {
                                    RoleIconView(role: role.raw, gameType: gameType, size: iconSize)
                                    if role.count > 1 {
                                        Text("\(role.count)")
                                            .font(.caption2.weight(.bold).monospacedDigit())
                                            .foregroundStyle(UMTheme.muted)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if !banished.isEmpty {
                            Button {
                                showBanished = true
                            } label: {
                                banishedPoolIcon
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Banished pool")
                        }
                    }
                    .padding(.horizontal, compact ? 0 : 12)
                    .padding(.vertical, compact ? 2 : 8)
                }
            }
            .background(compact ? Color.clear : UMTheme.card)
            .sheet(item: $selected) { role in
                RoleDetailsSheet(
                    roleRaw: role.raw,
                    gameType: gameType,
                    otherRoles: otherRoles
                )
            }
            .sheet(isPresented: $showBanished) {
                BanishedPoolSheet(
                    gameType: gameType,
                    banished: banished,
                    otherRoles: otherRoles
                )
            }
        }
    }

    @ViewBuilder
    private var banishedPoolIcon: some View {
        Group {
            if let url = RoleArt.banishedPoolURL {
                AnimatedWebPView(url: url, showsPlaceholder: false)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(UMTheme.muted)
                    .frame(width: iconSize, height: iconSize)
            }
        }
    }
}

struct SetupRoleStrip: View {
    var session: GameSession

    var body: some View {
        SetupPreviewStrip(
            gameType: session.setupGameType,
            rolesets: session.setupRolesets,
            banished: session.setupBanished,
            isSimpleMulti: session.isSimpleMulti,
            displayedRoles: session.setupRoles,
            onCycle: { session.cycleSetupRoleset() },
            compact: false
        )
    }
}

struct BanishedPoolSheet: View {
    var gameType: String
    var banished: [SetupRole]
    var otherRoles: [String]
    @State private var selected: SetupRole?
    @Environment(\.dismiss) private var dismiss

    init(session: GameSession) {
        self.gameType = session.setupGameType
        self.banished = session.setupBanished
        self.otherRoles = session.guessableRoles.map(\.raw)
    }

    init(gameType: String, banished: [SetupRole], otherRoles: [String]) {
        self.gameType = gameType
        self.banished = banished
        self.otherRoles = otherRoles
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 12)], spacing: 14) {
                    ForEach(banished) { role in
                        Button {
                            selected = role
                        } label: {
                            VStack(spacing: 4) {
                                RoleIconView(role: role.raw, gameType: gameType, size: 36)
                                if role.count > 1 {
                                    Text("\(role.count)")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                        .foregroundStyle(UMTheme.muted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(role.name)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(UMTheme.bg.ignoresSafeArea())
            .navigationTitle("Banished Pool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selected) { role in
                RoleDetailsSheet(
                    roleRaw: role.raw,
                    gameType: gameType,
                    otherRoles: otherRoles
                )
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct RoleDetailsSheet: View {
    var gameType: String
    var otherRoles: [String]
    /// The role being shown; "See also" chips swap it in place.
    @State private var roleRaw: String
    @Environment(\.dismiss) private var dismiss

    init(roleRaw: String, gameType: String, otherRoles: [String]) {
        self.gameType = gameType
        self.otherRoles = otherRoles
        _roleRaw = State(initialValue: roleRaw)
    }

    /// "See also: Quack (Mafia), Witch Doctor (Cult)." -> ["Quack", "Witch Doctor"]
    static func seeAlsoNames(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("see also") else { return nil }
        var rest = trimmed.dropFirst("see also".count).drop { $0 == ":" || $0 == " " }
        if rest.hasSuffix(".") { rest = rest.dropLast() }
        let names = rest.split(separator: ",").map { part -> String in
            var name = part.trimmingCharacters(in: .whitespaces)
            if let paren = name.range(of: " (", options: .backwards) { name = String(name[..<paren.lowerBound]) }
            return name
        }.filter { !$0.isEmpty }
        return names.isEmpty ? nil : names
    }

    var body: some View {
        let details = RoleCatalog.shared.details(roleRaw: roleRaw, gameType: gameType, otherRoles: otherRoles)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        RoleIconView(role: roleRaw, gameType: gameType, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(details.name)
                                .font(.title3.weight(.bold))
                            if let alignment = details.alignment, !alignment.isEmpty {
                                Text(alignment)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(alignmentColor(alignment))
                            }
                        }
                    }
                    if !details.tags.isEmpty {
                        Text(details.tags.sorted().joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(UMTheme.muted)
                    }
                    if details.lines.isEmpty, details.modifiers.isEmpty, !RoleCatalog.shared.isReady {
                        ProgressView()
                            .tint(UMTheme.blood)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                    ForEach(Array(details.lines.enumerated()), id: \.offset) { _, line in
                        if let names = Self.seeAlsoNames(line) {
                            seeAlsoRow(names)
                        } else {
                            Text(line)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !details.modifiers.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Modifiers")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(UMTheme.muted)
                            ForEach(details.modifiers) { mod in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        if let url = RoleArt.modifierURL(gameType: gameType, name: mod.name) {
                                            AnimatedWebPView(url: url, showsPlaceholder: false)
                                                .frame(width: 18, height: 18)
                                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                        }
                                        Text(mod.count > 1 ? "\(mod.name) x\(mod.count)" : mod.name)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    if !mod.text.isEmpty {
                                        Text(mod.text)
                                            .font(.subheadline)
                                            .foregroundStyle(UMTheme.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    if !details.specials.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Special interactions")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(UMTheme.muted)
                            ForEach(details.specials) { special in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(special.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(special.text)
                                        .font(.subheadline)
                                        .foregroundStyle(UMTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(UMTheme.bg.ignoresSafeArea())
            .navigationTitle(details.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await RoleCatalog.shared.load() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func seeAlsoRow(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("See also")
                .font(.caption.weight(.bold))
                .foregroundStyle(UMTheme.muted)
            ForEach(names, id: \.self) { name in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { roleRaw = name }
                } label: {
                    HStack(spacing: 6) {
                        RoleIconView(role: name, gameType: gameType, size: 20)
                        Text(name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(UMTheme.roleMention)
                        if let a = RoleCatalog.shared.alignment(of: name, gameType: gameType) {
                            Text("(\(a))")
                                .font(.subheadline)
                                .foregroundStyle(alignmentColor(a))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the \(name) role")
            }
        }
    }

    private func alignmentColor(_ alignment: String) -> Color {
        switch alignment.lowercased() {
        case "village", "town": return UMTheme.village
        case "mafia": return UMTheme.mafia
        case "cult": return Color.purple
        default: return UMTheme.muted
        }
    }
}

struct RoleGuessBadge: View {
    var session: GameSession
    var player: GamePlayer
    var onNeedPick: () -> Void

    var body: some View {
        let guess = session.displayedGuess(for: player.id)
        Button(action: tap) {
            ZStack(alignment: .bottomTrailing) {
                switch guess {
                case .unknown:
                    ZStack {
                        RoundedRectangle(cornerRadius: 4).fill(UMTheme.elevated)
                        Text("?")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(UMTheme.muted)
                    }
                    .frame(width: 30, height: 30)
                case .maybe(let role), .sure(let role):
                    RoleIconView(role: role, gameType: session.setupGameType, size: 30)
                }
                if guess.isUncertain {
                    Text("?")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.white, in: Capsule())
                        .offset(x: 4, y: 4)
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .disabled(player.id == session.selfId)
        .opacity(player.id == session.selfId ? 0.95 : 1)
    }

    private func tap() {
        if session.cycleRoleGuess(playerId: player.id) == .needsRolePick {
            onNeedPick()
        }
    }
}
