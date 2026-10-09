import Foundation
import Observation

struct RoleModifierLine: Identifiable, Hashable {
    var id: String { "\(name)#\(count)" }
    var name: String
    var count: Int
    var text: String
}

struct RoleSpecialLine: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var text: String
}

struct RoleDetails: Identifiable, Hashable {
    var id: String { raw }
    var raw: String
    var name: String
    var alignment: String?
    var tags: [String]
    var lines: [String]
    var modifiers: [RoleModifierLine]
    var specials: [RoleSpecialLine]
}

@Observable
final class RoleCatalog {
    static let shared = RoleCatalog()

    private(set) var isReady = false
    private var rolesByGame: [String: [String: [String: Any]]] = [:]
    private var modifiersByGame: [String: [String: [String: Any]]] = [:]
    private var mentionRegex: [String: NSRegularExpression] = [:]
    private var mentionMap: [String: [String: String]] = [:]
    private var loadTask: Task<Void, Never>?

    func load() async {
        if isReady { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await self.fetch() }
        loadTask = task
        await task.value
    }

    private func fetch() async {
        do {
            async let rawTask = APIClient.shared.jsonObject("roles/raw")
            async let modsTask = APIClient.shared.jsonObject("roles/modifiers")
            let raw = try await rawTask
            let mods = try await modsTask
            rolesByGame = Self.parseRoles(raw)
            modifiersByGame = Self.parseModifiers(mods)
            rebuildMentionIndex()
            isReady = true
        } catch {
            isReady = false
            loadTask = nil
        }
    }

    func alignment(of name: String, gameType: String) -> String? {
        rolesByGame[gameType]?[name]?["alignment"] as? String
    }

    func mentions(in text: String, gameType: String) -> [(range: Range<String.Index>, name: String)] {
        guard let regex = mentionRegex[gameType] ?? mentionRegex["Mafia"],
              let map = mentionMap[gameType] ?? mentionMap["Mafia"]
        else { return [] }
        let full = NSRange(location: 0, length: (text as NSString).length)
        var out: [(range: Range<String.Index>, name: String)] = []
        regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match, let range = Range(match.range, in: text) else { return }
            let raw = String(text[range])
            out.append((range, map[raw.lowercased()] ?? raw))
        }
        return out
    }

    private func rebuildMentionIndex() {
        mentionRegex.removeAll()
        mentionMap.removeAll()
        for (game, roles) in rolesByGame {
            let names = roles.keys.filter { $0.count >= 2 }
            var map: [String: String] = [:]
            for name in names { map[name.lowercased()] = name }
            mentionMap[game] = map
            let sorted = names.sorted { $0.count > $1.count }
            let pattern = sorted.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            guard !pattern.isEmpty else { continue }
            let full = "(?<!['’])\\b(?:\(pattern))\\b(?!['’])"
            mentionRegex[game] = try? NSRegularExpression(pattern: full, options: [.caseInsensitive])
        }
    }

    func details(roleRaw: String, gameType: String, otherRoles: [String]) -> RoleDetails {
        let name = roleRaw.split(separator: ":").first.map(String.init) ?? roleRaw
        let modifierNames: [String] = {
            let parts = roleRaw.split(separator: ":", maxSplits: 1)
            guard parts.count > 1 else { return [] }
            return parts[1].split(separator: "/").map(String.init).filter { !$0.isEmpty }
        }()

        let rawRole = rolesByGame[gameType]?[name] ?? [:]
        let alignment = rawRole["alignment"] as? String
        let tags = (rawRole["tags"] as? [String]) ?? []
        let lines: [String] = {
            if let arr = rawRole["description"] as? [String] { return arr.filter { !$0.isEmpty } }
            if let s = rawRole["description"] as? String, !s.isEmpty { return [s] }
            return []
        }()

        let specialMod = rawRole["SpecialInteractionsModifiers"] as? [String: Any]
        var modifierLines: [RoleModifierLine] = []
        var seen = Set<String>()
        for modName in modifierNames {
            if seen.contains(modName) { continue }
            seen.insert(modName)
            let count = modifierNames.filter { $0 == modName }.count
            let rec = modifiersByGame[gameType]?[modName] ?? [:]
            var text = ""
            if let special = stringList(specialMod?[modName]).first, !special.isEmpty {
                text = special
            } else if alignment == "Event", let event = rec["eventDescription"] as? String, !event.isEmpty {
                text = event
            } else if let d = rec["description"] as? String {
                text = d
            }
            text = text.replacingOccurrences(of: "[X]", with: "\(count)")
            modifierLines.append(RoleModifierLine(name: modName, count: count, text: text))
        }

        var specials: [RoleSpecialLine] = []
        if let map = rawRole["SpecialInteractions"] as? [String: Any] {
            var used = Set<String>()
            for other in otherRoles {
                let otherName = other.split(separator: ":").first.map(String.init) ?? other
                guard otherName != name, !used.contains(otherName) else { continue }
                if let line = stringList(map[otherName]).first, !line.isEmpty {
                    used.insert(otherName)
                    specials.append(RoleSpecialLine(name: otherName, text: line))
                }
            }
        }

        return RoleDetails(
            raw: roleRaw,
            name: name,
            alignment: alignment,
            tags: tags,
            lines: lines,
            modifiers: modifierLines,
            specials: specials
        )
    }

    private func stringList(_ value: Any?) -> [String] {
        if let arr = value as? [String] { return arr }
        if let arr = value as? [Any] { return arr.compactMap { $0 as? String } }
        if let s = value as? String { return [s] }
        return []
    }

    private static func parseRoles(_ raw: Any) -> [String: [String: [String: Any]]] {
        guard let games = raw as? [String: Any] else { return [:] }
        var out: [String: [String: [String: Any]]] = [:]
        for (game, val) in games {
            guard let roles = val as? [String: Any] else { continue }
            var inner: [String: [String: Any]] = [:]
            for (name, rv) in roles {
                inner[name] = rv as? [String: Any] ?? [:]
            }
            out[game] = inner
        }
        return out
    }

    private static func parseModifiers(_ raw: Any) -> [String: [String: [String: Any]]] {
        guard let games = raw as? [String: Any] else { return [:] }
        var out: [String: [String: [String: Any]]] = [:]
        for (game, val) in games {
            var byName: [String: [String: Any]] = [:]
            if let list = val as? [[String: Any]] {
                for item in list {
                    if let name = item["name"] as? String {
                        byName[name] = item
                    }
                }
            } else if let dict = val as? [String: Any] {
                for (name, rv) in dict {
                    byName[name] = rv as? [String: Any] ?? [:]
                }
            }
            out[game] = byName
        }
        return out
    }
}
