import SwiftUI

/// Liars Dice (server Games/types/LiarsDice): one "Guess Dice" state per turn. Each state's
/// `extraInfo` carries the table (randomizedPlayers with rolledDice/previousRolls), whose turn it
/// is (whoseTurnIsIt = user id) and bidInfo. The current bidder holds the Microphone item, which
/// gives the meetings Amount (text, numeric), Face (imageButtons dice1…dice6), CallLie and SpotOn
/// (button "Yes!"); separationText is a display-only "OR".
nonisolated struct LDPlayer: Identifiable, Hashable {
    var playerId: String
    var userId: String?
    var name: String
    var avatar: Bool
    var dice: [Int]
    var previous: [Int]
    var id: String { playerId }
}

nonisolated struct LDState: Hashable {
    var players: [LDPlayer]
    var whoseTurnUserId: String?
    var flyingDutchman: Bool
    var allDice: Int
    var lastAmount: Int
    var lastFace: Int
    var lastBidder: String?
    var currentBidder: String?
    var uhhVariant: Int?
    var geniusVariant: Int?
    var annoyedJustTriggered: Bool

    static let importantMeetings: Set<String> = ["Amount", "Face", "CallLie", "SpotOn", "separationText"]

    init?(_ extra: Any?) {
        guard let x = extra as? [String: Any], let list = x["randomizedPlayers"] as? [Any] else { return nil }
        func int(_ a: Any?) -> Int? {
            if let i = a as? Int { return i }
            if let d = a as? Double { return Int(d) }
            if let s = a as? String { return Int(s) }
            return nil
        }
        func ints(_ a: Any?) -> [Int] { (a as? [Any] ?? []).compactMap(int) }
        players = list.compactMap { any in
            guard let p = any as? [String: Any], let pid = p["playerId"] as? String else { return nil }
            return LDPlayer(playerId: pid, userId: p["userId"] as? String,
                            name: p["playerName"] as? String ?? "Player",
                            avatar: (p["avatar"] as? Bool) ?? false,
                            dice: ints(p["rolledDice"]), previous: ints(p["previousRolls"]))
        }
        whoseTurnUserId = x["whoseTurnIsIt"] as? String
        flyingDutchman = (x["isTheFlyingDutchman"] as? Bool) ?? false
        let b = x["bidInfo"] as? [String: Any] ?? [:]
        allDice = int(b["allDice"]) ?? 0
        lastAmount = int(b["lastAmountBid"]) ?? 0
        lastFace = int(b["lastFaceBid"]) ?? 1
        lastBidder = b["lastBidder"] as? String
        currentBidder = b["currentBidder"] as? String
        uhhVariant = int(b["uhhVariant"])
        geniusVariant = int(b["geniusVariant"])
        annoyedJustTriggered = (b["annoyedJustTriggered"] as? Bool) ?? false
    }
}

struct LDDie: View {
    var face: Int?     // nil = hidden
    var size: CGFloat = 26
    var dim = false
    var body: some View {
        Group {
            if let f = face, (1...6).contains(f) {
                Image(systemName: "die.face.\(f).fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(.white, UMTheme.elevated)
            } else {
                Image(systemName: "questionmark.square.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(UMTheme.muted)
            }
        }
        .frame(width: size, height: size)
        .opacity(dim ? 0.6 : 1)
        .accessibilityLabel(face.map { "\($0)" } ?? "hidden die")
    }
}

struct LiarsDiceBoard: View {
    var session: GameSession
    @State private var amount = 1
    @State private var face: Int?
    @State private var bidError = ""

    private var state: LDState? { session.ldViewing }
    private var live: Bool { session.isViewingLive && !session.finished && !session.isReview }
    private func meeting(_ name: String) -> VoteMeeting? {
        live ? session.meetings.first { $0.name == name && $0.amMember } : nil
    }
    private var isMyTurn: Bool { meeting("Amount") != nil && meeting("Face") != nil }

    var body: some View {
        if let st = state {
            VStack(alignment: .leading, spacing: 12) {
                table(st)
                bidCard(st)
                betLog
            }
            .onChange(of: st.lastAmount, initial: true) { _, last in
                amount = last + 1; bidError = ""
            }
            .onChange(of: st.lastBidder) { _, _ in face = nil; bidError = "" }
        } else if session.currentPhaseId < 0 {
            Text("Dice are rolled when the game starts.")
                .font(.subheadline).foregroundStyle(UMTheme.muted)
        }
    }

    private func table(_ st: LDState) -> some View {
        let bets = session.ldCurrentRoundBets
        return VStack(spacing: 8) {
            ForEach(st.players) { p in
                let turn = p.userId != nil && p.userId == st.whoseTurnUserId
                let mine = p.playerId == session.selfId
                // Web shows only your own dice; reviews (finished games) reveal everyone's.
                let reveal = mine || session.isReview
                HStack(alignment: .top, spacing: 10) {
                    UMAvatarView(userId: p.userId, hasAvatar: p.avatar, name: p.name, size: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            if turn { Circle().fill(UMTheme.blood).frame(width: 7, height: 7) }
                            Text(p.name).font(.subheadline.weight(mine ? .bold : .semibold)).lineLimit(1)
                            if mine { Text("(you)").font(.caption).foregroundStyle(UMTheme.muted) }
                            if let b = bets[p.name] {
                                HStack(spacing: 2) {
                                    Text("\(b.amount)×").font(.caption.monospacedDigit().weight(.semibold))
                                    LDDie(face: b.face, size: 14)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(UMTheme.elevated, in: Capsule())
                                .accessibilityLabel("Bet \(b.amount) of \(b.face)")
                            }
                            Spacer(minLength: 4)
                            Text("\(p.dice.count) \(p.dice.count == 1 ? "die" : "dice")")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(UMTheme.muted)
                        }
                        HStack(spacing: 4) {
                            ForEach(Array(p.dice.enumerated()), id: \.offset) { _, v in
                                LDDie(face: reveal ? v : nil, size: 24)
                            }
                            if p.dice.isEmpty { Text("No dice").font(.caption).foregroundStyle(UMTheme.muted) }
                        }
                        if !p.previous.isEmpty {
                            HStack(spacing: 3) {
                                Text("Prior round:").font(.caption2).foregroundStyle(st.flyingDutchman ? Color(red: 0.23, green: 0.35, blue: 0.25) : UMTheme.muted)
                                ForEach(Array(p.previous.enumerated()), id: \.offset) { _, v in
                                    LDDie(face: v, size: 14, dim: true)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(turn ? Color.gray : .clear, lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func bidCard(_ st: LDState) -> some View {
        let hasPrior = st.lastBidder != nil
        if hasPrior || isMyTurn || live {
            VStack(alignment: .leading, spacing: 10) {
                if let who = st.lastBidder {
                    HStack(alignment: .center, spacing: 6) {
                        Text(bidText(st, who: who)).font(.subheadline)
                        LDDie(face: st.lastFace, size: 20)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let cur = st.currentBidder, !isMyTurn, live {
                    Text("Waiting for \(cur) to bid…").font(.subheadline).foregroundStyle(UMTheme.muted)
                }
                if st.annoyedJustTriggered {
                    Text("For the rest of the round, bids can only increase amount by 1.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if isMyTurn || live {
                    betForm(st).disabled(!isMyTurn).opacity(isMyTurn ? 1 : 0.5)
                    actionRow(st)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func bidText(_ st: LDState, who: String) -> String {
        if st.geniusVariant != nil {
            return "We have a genius in here! \(who) thinks there are \(st.lastAmount)× among these \(st.allDice):"
        }
        if st.uhhVariant != nil { return "\(who) guesses uhh.. \(st.lastAmount)×" }
        return "\(who) guesses at least \(st.lastAmount)×"
    }

    private func betForm(_ st: LDState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Up the bet!").font(.headline)
            HStack {
                Text("There are at least").font(.subheadline)
                Picker("Amount", selection: $amount) {
                    ForEach(amountRange(st), id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                .tint(.white)
                Text("×").font(.subheadline)
            }
            HStack(spacing: 6) {
                ForEach(1...6, id: \.self) { f in
                    Button { face = f } label: {
                        LDDie(face: f, size: 34)
                            .padding(3)
                            .background(face == f ? UMTheme.blood.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Face \(f)")
                    .accessibilityAddTraits(face == f ? .isSelected : [])
                }
            }
            if !bidError.isEmpty { Text(bidError).font(.caption).foregroundStyle(UMTheme.mafia) }
        }
    }

    /// CALL BLUFF | SPOT ON | SUBMIT: three equal-width buttons in one row.
    private func actionRow(_ st: LDState) -> some View {
        let lie = meeting("CallLie"), spot = meeting("SpotOn")
        func label(_ t: String) -> some View {
            Text(t).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        return HStack(spacing: 8) {
            Button { if let m = lie { session.vote(meetingId: m.id, selection: "Yes!") } } label: { label("CALL BLUFF") }
                .buttonStyle(.borderedProminent).tint(UMTheme.blood).disabled(lie == nil)
            Button { if let m = spot { session.vote(meetingId: m.id, selection: "Yes!") } } label: { label("SPOT ON") }
                .buttonStyle(.borderedProminent).tint(.orange).disabled(spot == nil)
            Button { submit(st) } label: { label("SUBMIT") }
                .buttonStyle(.borderedProminent).tint(UMTheme.village)
                .disabled(!isMyTurn || face == nil || amount < 1)
        }
    }

    private func amountRange(_ st: LDState) -> [Int] {
        let lo = max(1, st.lastAmount)
        let hi = max(lo + 5, st.allDice, amount)
        return Array(lo...hi)
    }

    @ViewBuilder
    private var betLog: some View {
        @Bindable var s = session
        let rounds = session.ldRounds.reversed()   // newest round first
        VStack(alignment: .leading, spacing: 6) {
            Text("Bet log").font(.headline)
            if let current = rounds.first {
                roundView(current)
                let prior = Array(rounds.dropFirst())
                if !prior.isEmpty {
                    DisclosureGroup(isExpanded: $s.ldShowPriorRounds) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(prior) { roundView($0) }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text("Prior rounds (\(prior.count))").font(.subheadline.weight(.semibold))
                    }
                    .tint(UMTheme.muted)
                }
            } else {
                Text("No bids yet.").font(.caption).foregroundStyle(UMTheme.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Reverse chronological: the challenge result (if the round ended) on top, then bids newest first.
    private func roundView(_ r: LDRound) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Round \(r.number)").font(.caption.weight(.bold)).foregroundStyle(UMTheme.muted).padding(.top, 4)
            ForEach(Array(r.alerts.reversed().enumerated()), id: \.offset) { _, text in
                EmoteText(text: text, color: UMTheme.muted, italic: true, system: true, emoteSize: 14,
                          players: session.players, gameType: session.setupGameType, otherRoles: [])
            }
            ForEach(Array(r.bids.reversed().enumerated()), id: \.offset) { _, b in
                HStack(spacing: 4) {
                    Text("\(b.who) bid \(b.amount)×").font(.subheadline)
                    LDDie(face: b.face, size: 16)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func submit(_ st: LDState) {
        guard let face, let a = meeting("Amount"), let f = meeting("Face") else { return }
        if amount < st.lastAmount { bidError = "You can't bid lower than the previous player."; return }
        if st.lastBidder != nil, amount == st.lastAmount, face <= st.lastFace {
            bidError = "You must increase either the amount or the face value of the previous bid."; return
        }
        bidError = ""
        session.vote(meetingId: a.id, selection: String(amount))
        // Web staggers the second vote 200ms: the server's vote rate limit penalizes near-zero gaps.
        let faceId = f.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            session.vote(meetingId: faceId, selection: "dice\(face)")
        }
    }
}


struct LDRound: Identifiable {
    struct Bid { var who: String; var amount: Int; var face: Int }
    var number: Int
    var bids: [Bid] = []
    var alerts: [String] = []
    var id: Int { number }
}

extension GameSession {
    /// Rounds in play order, built from the saved turn states (a bid whenever the last bid changes)
    /// plus that turn's challenge alerts; a bid reset starts the next round.
    var ldRounds: [LDRound] {
        var rounds: [LDRound] = []
        var prev: LDState?
        var number = 1
        func cur() -> Int {
            if rounds.last?.number != number { rounds.append(LDRound(number: number)) }
            return rounds.count - 1
        }
        for (k, st) in ldByPhase.sorted(by: { $0.key < $1.key }) where k >= 0 {
            if st.lastBidder == nil, prev?.lastBidder != nil { number += 1 }
            if let b = st.lastBidder,
               prev?.lastBidder != b || prev?.lastAmount != st.lastAmount || prev?.lastFace != st.lastFace {
                rounds[cur()].bids.append(.init(who: b, amount: st.lastAmount, face: st.lastFace))
            }
            for line in phases.first(where: { $0.id == k })?.messages ?? [] where line.isServer {
                let t = line.content.lowercased()
                if t.contains("called a bluff") || t.contains("called a lie") || t.contains("spot on") || t.contains("loses a die") || t.contains("lose a die") {
                    rounds[cur()].alerts.append(line.content)
                }
            }
            prev = st
        }
        return rounds
    }
}

extension GameSession {
    /// Each bidder's latest bid in the current round (keyed by player name, as bidInfo names them).
    var ldCurrentRoundBets: [String: (amount: Int, face: Int)] {
        var out: [String: (amount: Int, face: Int)] = [:]
        var prev: LDState?
        for (k, st) in ldByPhase.sorted(by: { $0.key < $1.key }) where k >= 0 {
            if st.lastBidder == nil, prev?.lastBidder != nil { out = [:] }
            if let b = st.lastBidder { out[b] = (st.lastAmount, st.lastFace) }
            prev = st
        }
        return out
    }
}

/// Live Liars Dice cues, fed one new turn state at a time (never during history/review).
enum LDEvents {
    /// Dice-falling sound for round start/end: set the GameSFX name once Pranay confirms the
    /// file and when it plays. nil = no sound (intentionally not guessed).
    static var diceFallSound: String? = nil

    @MainActor
    static func handle(old: LDState?, new: LDState, selfId: String?) {
        let bid = new.lastBidder != nil &&
            (old?.lastBidder != new.lastBidder || old?.lastAmount != new.lastAmount || old?.lastFace != new.lastFace)
        if bid { GameSFX.play("ping") }
        let roundStart = old == nil || (new.lastBidder == nil && old?.lastBidder != nil)
        if roundStart, let s = diceFallSound { GameSFX.play(s) }
        let myTurn = new.players.first { $0.userId != nil && $0.userId == new.whoseTurnUserId }?.playerId
        if let me = selfId, myTurn == me, old?.whoseTurnUserId != new.whoseTurnUserId {
            GameAlerts.notifyYourTurn()
        }
    }
}
