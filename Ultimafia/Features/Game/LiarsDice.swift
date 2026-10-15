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
        VStack(spacing: 8) {
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
                        }
                        HStack(spacing: 4) {
                            ForEach(Array(p.dice.enumerated()), id: \.offset) { _, v in
                                LDDie(face: reveal ? v : nil, size: 24)
                            }
                            if p.dice.isEmpty { Text("No dice").font(.caption).foregroundStyle(UMTheme.muted) }
                        }
                        if !p.previous.isEmpty {
                            HStack(spacing: 3) {
                                Text("Last round:").font(.caption2).foregroundStyle(st.flyingDutchman ? Color(red: 0.23, green: 0.35, blue: 0.25) : UMTheme.muted)
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
        if hasPrior || isMyTurn || !(st.currentBidder ?? "").isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let who = st.lastBidder {
                    HStack(alignment: .center, spacing: 6) {
                        Text(bidText(st, who: who)).font(.subheadline)
                        LDDie(face: st.lastFace, size: 20)
                    }
                    .accessibilityElement(children: .combine)
                    if isMyTurn {
                        HStack(spacing: 8) {
                            if let m = meeting("CallLie") {
                                Button("CALL BLUFF") { session.vote(meetingId: m.id, selection: "Yes!") }
                                    .buttonStyle(.borderedProminent).tint(UMTheme.blood)
                            }
                            if let m = meeting("SpotOn") {
                                Button("SPOT ON") { session.vote(meetingId: m.id, selection: "Yes!") }
                                    .buttonStyle(.borderedProminent).tint(.orange)
                            }
                        }
                        .font(.subheadline.weight(.bold))
                    }
                } else if let cur = st.currentBidder, !isMyTurn, live {
                    Text("Waiting for \(cur) to bid…").font(.subheadline).foregroundStyle(UMTheme.muted)
                }
                if st.annoyedJustTriggered {
                    Text("For the rest of the round, bids can only increase amount by 1.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if isMyTurn { betForm(st) }
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
                TextField("", value: $amount, format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                Stepper("", value: $amount, in: 1...99_999).labelsHidden()
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
            Button {
                submit(st)
            } label: {
                Text("BET").font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(UMTheme.blood)
            .disabled(face == nil || amount < 1)
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
