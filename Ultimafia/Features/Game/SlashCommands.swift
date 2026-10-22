import Foundation

/// Chat slash commands. Contracts (UltiMafia server, Games/core + Games/types/Mafia):
/// - /kick, /ban, /extend: sent as a normal `speak` whose content starts with "/"; the server's
///   Player.parseCommand handles them (kick/ban: pregame, host only, not competitive, exact
///   case-insensitive name; extend: Day, alive, once per player). Nothing is posted to chat.
/// - /vote, /unvote, /shoot: socket `vote` / `unvote` {meetingId, selection} on the village
///   meeting / the Gun item meeting (actionName "Shoot"), restricted to the server's `targets`.
/// - /whisper: `speak` {meetingId, content, abilityName: "Whisper", abilityTarget: playerId},
///   plus `forceLeak: true` when "Leak Whispers" is on. Only offered when setup.gameSettings
///   "Whispers" is on AND the meeting carries the Whisper speech ability (not Pregame/anonymous);
///   "Whisper Leak Chance" is shown in the summary.
/// - in-game /kick (no name): the veg "Vote Kick" meeting (core/VegKickMeeting.js) that appears
///   when the phase timer runs out: socket `vote` {meetingId, selection: "Kick"}; canUnvote is
///   always false; canVote = alive && voted in all other meetings. Progress is only broadcast as
///   the alert "Kicking… n / ceil(alive/3)"; at the threshold the 15s "vegKick" timer starts.
/// - /cry: `speak` {abilityName: "Cry", abilityTarget: "out"} when the Cry ability is offered
///   (Crier's BroadcastMessage card); the server re-sends it anonymously with prefix "cries out".
/// - /join, /spectate: handled in the app, because live master has no such chat commands (PR
///   #3093 isn't merged). /join = the desktop "Join open seat" button (`takeSeat`; refusals come
///   back as `takeSeatFailed`). /spectate = the desktop Spectate button (rejoin with
///   `?spectate=true`; a refusal comes back as `spectateFailed`).
/// - /wave, /shake, /glow, /rainbow, /slide, /flash (site PR #3090): `speak` with the command in
///   the content; the server strips it and attaches `textEffect` for owners of Advanced Text
///   Effects, or answers with a notice. Offered in the bar only to owners.
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
    private static let serverCommands: Set<String> = Set([
        "me", "role", "item", "modifier", "achievement", "diceroll", "nightorder", "help", "daily",
    ] + UMTextEffect.allCases.map(\.rawValue))

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

    /// Live veg/vote-kick meeting you're in (any phase).
    var kickMeeting: VoteMeeting? {
        guard isViewingLive, !isReview, !spectate else { return nil }
        return meetings.first { $0.isVoteKick && $0.amMember }
    }

    var hasKicked: Bool {
        guard let m = kickMeeting else { return false }
        return !m.selections(of: selfId).isEmpty || m.playerHasVoted
    }

    /// Latest "Kicking… n / m" alert (votes are invisible, so this is the only count the server sends).
    var kickProgress: (count: Int, needed: Int)? {
        guard kickMeeting != nil else { return nil }
        for line in messages.reversed() where line.isServer {
            let t = line.content
            guard let r = t.range(of: #"Kicking\S*\s+(\d+)\s*/\s*(\d+)"#, options: .regularExpression) else { continue }
            let nums = t[r].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if nums.count >= 2 { return (nums[0], nums[1]) }
        }
        let alive = players.filter { !deadIds.contains($0.id) && !$0.left }.count
        return (0, max(1, Int((Double(alive) / 3).rounded(.up))))
    }

    /// Web Kick button: one "Kick" vote; server ignores repeats and never allows unkick.
    func sendKick() {
        guard let m = kickMeeting, m.canVote, !hasKicked else { return }
        socketForCommands.send("vote", object: ["meetingId": m.id, "selection": "Kick"])
    }

    var gunMeeting: VoteMeeting? {
        meetings.first { $0.canVote && $0.amMember && ($0.actionName == "Shoot" || $0.name.hasPrefix("Shoot Gun")) }
    }

    private func abilityChannel(_ ability: String) -> (channel: SpeechChannel, ability: SpeechAbility)? {
        if ability == "Whisper" && !setupWhispers { return nil }
        for ch in speechChannels where ch.canTalk {
            if let a = ch.abilities.first(where: { $0.name == ability }) { return (ch, a) }
        }
        return nil
    }

    var availableSlashCommands: [SlashCommand] {
        guard isViewingLive, !isReview else { return [] }
        var out: [SlashCommand] = []
        // Seats (site #3093), for everyone in pregame: spectators sit down, seated players watch.
        if canTakeSeat {
            out.append(SlashCommand(name: "join", usage: "/join", summary: "Take an open seat in the game", icon: "chair.fill", arg: .none))
        }
        if canSpectateFromSeat {
            out.append(SlashCommand(name: "spectate", usage: "/spectate", summary: "Give up your seat and watch as a spectator", icon: "eye", arg: .none))
        }
        // Text effects (site #3090) wherever you can talk, listed last; the server checks the item.
        var effects: [SlashCommand] = []
        if UMTextEffects.owned, speechChannels.contains(where: { $0.canTalk }) {
            effects = UMTextEffect.allCases.map { e in
                SlashCommand(name: e.rawValue, usage: "/\(e.rawValue) text", summary: e.summary, icon: e.icon, arg: .text)
            }
        }
        guard !spectate else { return out + effects }
        if isPregame {
            if isHost && !competitiveGame {
                out.append(SlashCommand(name: "kick", usage: "/kick name", summary: "Remove a player from the lobby", icon: "person.fill.xmark", arg: .player))
                out.append(SlashCommand(name: "ban", usage: "/ban name", summary: "Remove and ban a player from the lobby", icon: "nosign", arg: .player))
            }
        } else {
            if let k = kickMeeting, k.canVote, !hasKicked {
                out.append(SlashCommand(name: "kick", usage: "/kick", summary: "Vote to kick vegging players", icon: "figure.walk.departure", arg: .none))
            }
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
            out.append(SlashCommand(name: "whisper", usage: "/whisper name message", summary: whisperSummary, icon: "ear", arg: .playerThenText))
        }
        if abilityChannel("Cry") != nil {
            out.append(SlashCommand(name: "cry", usage: "/cry message", summary: "Cry out anonymously to everyone", icon: "megaphone.fill", arg: .text))
        }
        return out + effects
    }

    private var whisperSummary: String {
        var s = "Whisper privately to a player"
        if setupWhisperLeakChance > 0 { s += " (\(Int(setupWhisperLeakChance))% leak chance)" }
        if whisperForceLeak { s += " · leaking" }
        return s
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
        // Live master's server has no /join or /spectate chat command yet, so the app does what
        // the desktop buttons do: Join open seat = `takeSeat`; Spectate = rejoin with spectate.
        case "join":
            guard canTakeSeat else { return .error("You can only take a seat while spectating in pregame") }
            takeSeat()
            return .handled
        case "spectate":
            guard canSpectateFromSeat else { return .error("You can't spectate right now") }
            guard let onSpectateFromSeat else { return .error("You can't spectate right now") }
            onSpectateFromSeat()
            return .handled
        case "kick" where !isPregame:
            guard rest.isEmpty else { return .error("In-game /kick takes no name") }
            sendKick()
            return .handled
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
            let noOneWords: Set<String> = ["", "nl", "no one", "noone", "none", "nobody"]
            let wantsNoOne = noOneWords.contains(rest.lowercased())
            if selection == nil, wantsNoOne {
                // Must-condemn setups: the server leaves "*" out of targets and rejects it.
                selection = m.targets.contains("*") ? "*" : nil
            }
            guard let selection else {
                return .error(wantsNoOne ? "This setup requires a condemnation, so you can't vote no one." : "Can't vote “\(rest)”")
            }
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
            var payload: [String: Any] = [
                "meetingId": ch.id, "content": msg, "abilityName": "Whisper", "abilityTarget": p.id,
            ]
            if whisperForceLeak { payload["forceLeak"] = true }
            socketForCommands.send("speak", object: payload)
            return .handled
        case "cry":
            guard !rest.isEmpty else { return .error("Add a message: /cry message") }
            guard let (ch, _) = abilityChannel("Cry") else { return .error("You can't cry out") }
            socketForCommands.send("speak", object: [
                "meetingId": ch.id, "content": rest, "abilityName": "Cry",
                "abilityTarget": "out",
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
