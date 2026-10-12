import Foundation

/// Chat slash commands. Contracts (UltiMafia server, Games/core + Games/types/Mafia):
/// - /kick, /ban, /extend: sent as a normal `speak` whose content starts with "/"; the server's
///   Player.parseCommand handles them (kick/ban: pregame, host only, not competitive, exact
///   case-insensitive name; extend: Day, alive, once per player). Nothing is posted to chat.
/// - /vote, /unvote, /shoot: socket `vote` / `unvote` {meetingId, selection} on the village
///   meeting / the Gun item meeting (actionName "Shoot"), restricted to the server's `targets`.
/// - /whisper: `speak` {meetingId, content, abilityName: "Whisper", abilityTarget: playerId},
///   only when the meeting offers the Whisper speech ability (setup whispers on, not anonymous).
/// - /cry: `speak` {abilityName: "Cry", abilityTarget: "out"} when the Cry ability is offered
///   (Crier's BroadcastMessage card); the server re-sends it anonymously with prefix "cries out".
struct SlashCommand: Identifiable, Hashable {
    enum Arg { case none, player, playerThenText, text, optionalPlayer }
    var name: String
    var usage: String
    var summary: String
    var icon: String
    var arg: Arg
    var id: String { name }
}

enum SlashResult {
    case handled
    case error(String)
    case passThrough
}

extension GameSession {
    /// Commands the server parses itself and that the web lists (react_main constants/commandList).
    private static let serverCommands: Set<String> = [
        "me", "role", "item", "modifier", "achievement", "diceroll", "nightorder", "help", "daily",
    ]

    var isPregame: Bool { currentPhaseId == -1 }

    private var isDayPhase: Bool {
        (phases.first { $0.id == currentPhaseId }?.name ?? "").lowercased().hasPrefix("day")
    }

    var isHost: Bool {
        guard let hostId, let selfId else { return false }
        return players.first { $0.id == selfId }?.userId == hostId
    }

    private var selfAlive: Bool { selfId.map { !deadIds.contains($0) } ?? false }

    /// Village day meeting (web: the meeting you condemn in), else your main vote meeting.
    var villageMeeting: VoteMeeting? {
        let usable = meetings.filter { $0.canVote && $0.amMember && !$0.isVoteKick && $0.inputType == "player" }
        return usable.first { $0.name == "Village" } ?? usable.first { $0.actionName == "Vote to Condemn" } ?? usable.first
    }

    var gunMeeting: VoteMeeting? {
        meetings.first { $0.canVote && $0.amMember && ($0.actionName == "Shoot" || $0.name.hasPrefix("Shoot Gun")) }
    }

    private func abilityChannel(_ ability: String) -> (channel: SpeechChannel, ability: SpeechAbility)? {
        for ch in speechChannels where ch.canTalk {
            if let a = ch.abilities.first(where: { $0.name == ability }) { return (ch, a) }
        }
        return nil
    }

    var availableSlashCommands: [SlashCommand] {
        guard isViewingLive, !spectate else { return [] }
        var out: [SlashCommand] = []
        if isPregame {
            if isHost && !competitiveGame {
                out.append(SlashCommand(name: "kick", usage: "/kick name", summary: "Remove a player from the lobby", icon: "person.fill.xmark", arg: .player))
                out.append(SlashCommand(name: "ban", usage: "/ban name", summary: "Remove and ban a player from the lobby", icon: "nosign", arg: .player))
            }
        } else {
            if isDayPhase && selfAlive {
                out.append(SlashCommand(name: "extend", usage: "/extend", summary: "Vote to extend the day", icon: "clock.badge.plus", arg: .none))
            }
            if let m = villageMeeting {
                out.append(SlashCommand(name: "vote", usage: "/vote name", summary: "Vote in \(m.name); empty or nl = No one", icon: "hand.raised.fill", arg: .optionalPlayer))
                if m.canUnvote && !m.selections(of: selfId).isEmpty {
                    out.append(SlashCommand(name: "unvote", usage: "/unvote", summary: "Clear your vote", icon: "arrow.uturn.backward", arg: .none))
                }
            }
            if gunMeeting != nil {
                out.append(SlashCommand(name: "shoot", usage: "/shoot name", summary: "Shoot a player with your gun", icon: "scope", arg: .player))
            }
        }
        if abilityChannel("Whisper") != nil {
            out.append(SlashCommand(name: "whisper", usage: "/whisper name message", summary: "Whisper privately to a player", icon: "ear", arg: .playerThenText))
        }
        if abilityChannel("Cry") != nil {
            out.append(SlashCommand(name: "cry", usage: "/cry message", summary: "Cry out anonymously to everyone", icon: "megaphone.fill", arg: .text))
        }
        return out
    }

    /// Players a command can target, from the server's lists only.
    func slashTargets(for command: String) -> [GamePlayer] {
        let ids: [String]
        switch command {
        case "kick", "ban": ids = players.filter { $0.id != selfId && !$0.left }.map(\.id)
        case "vote": ids = villageMeeting?.targets ?? []
        case "shoot": ids = gunMeeting?.targets ?? []
        case "whisper": ids = abilityChannel("Whisper")?.ability.targets ?? []
        default: ids = []
        }
        return ids.compactMap { id in players.first { $0.id == id } }
    }

    private func exactPlayer(_ name: String, in list: [GamePlayer]) -> GamePlayer? {
        list.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func runSlashCommand(_ text: String) -> SlashResult {
        let body = String(text.dropFirst())
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let cmd = parts.first?.lowercased() else { return .error("Type a command after /") }
        let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        if Self.serverCommands.contains(cmd) { return .passThrough }
        guard let def = availableSlashCommands.first(where: { $0.name == cmd }) else {
            return .error("/\(cmd) isn't available right now")
        }
        switch def.name {
        case "kick", "ban":
            guard let p = exactPlayer(rest, in: slashTargets(for: cmd)) else { return .error("No player named “\(rest)”") }
            return sendServerCommand("/\(cmd) \(p.name)")
        case "extend":
            return sendServerCommand("/extend")
        case "vote":
            guard let m = villageMeeting else { return .error("No vote right now") }
            let targets = slashTargets(for: "vote")
            var selection: String?
            if let p = exactPlayer(rest, in: targets) { selection = p.id }
            else if rest.isEmpty || rest.lowercased() == "nl" { selection = m.targets.contains("*") ? "*" : nil }
            guard let selection else { return .error(rest.isEmpty || rest.lowercased() == "nl" ? "No one isn't an option here" : "Can't vote “\(rest)”") }
            if m.selections(of: selfId).contains(selection) { return .handled }
            vote(meetingId: m.id, selection: selection)
            return .handled
        case "unvote":
            guard let m = villageMeeting, m.canUnvote else { return .error("You can't unvote here") }
            for sel in m.selections(of: selfId) {
                socketForCommands.send("unvote", object: ["meetingId": m.id, "selection": sel])
            }
            return .handled
        case "shoot":
            guard let m = gunMeeting else { return .error("You have no gun to shoot") }
            guard !rest.contains(" "), let p = exactPlayer(rest, in: slashTargets(for: "shoot")) else {
                return .error("Shoot needs exactly one valid player")
            }
            if !m.selections(of: selfId).contains(p.id) { vote(meetingId: m.id, selection: p.id) }
            return .handled
        case "whisper":
            let bits = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let first = bits.first, let p = exactPlayer(String(first), in: slashTargets(for: "whisper")) else {
                return .error("Whisper to whom? /whisper name message")
            }
            let msg = bits.count > 1 ? String(bits[1]).trimmingCharacters(in: .whitespaces) : ""
            guard !msg.isEmpty else { return .error("Add a message after the name") }
            guard let ch = abilityChannel("Whisper")?.channel else { return .error("Whispers are off") }
            socketForCommands.send("speak", object: [
                "meetingId": ch.id, "content": msg, "abilityName": "Whisper", "abilityTarget": p.id,
            ])
            return .handled
        case "cry":
            guard !rest.isEmpty else { return .error("Add a message: /cry message") }
            guard let (ch, ability) = abilityChannel("Cry") else { return .error("You can't cry out") }
            socketForCommands.send("speak", object: [
                "meetingId": ch.id, "content": rest, "abilityName": "Cry",
                "abilityTarget": ability.targets.first ?? "out",
            ])
            return .handled
        default:
            return .error("Unknown command")
        }
    }

    private func sendServerCommand(_ content: String) -> SlashResult {
        let meetingId = selectedSpeechMeetingId ?? speechChannels.first(where: { $0.canTalk })?.id
        guard let meetingId else { return .error("Can't send commands right now") }
        socketForCommands.send("speak", object: ["meetingId": meetingId, "content": content])
        return .handled
    }
}
