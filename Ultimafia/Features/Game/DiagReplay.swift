#if DEBUG
import SwiftUI

/// DEBUG only. Launch with `-UMDiagReplay` to open a synthetic game (no network, no account) and
/// drive it through Day 1 -> Night 1 -> Day 2 with the same socket handlers, so phase-change stalls
/// and message latency show up in the diagnostics log / watchdog without joining a real game.
struct DiagReplayView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let replay = NavigationStack {
            GameView()
        }
        .task { await run() }
        // `-UMDiagWidth <pt> [compact|regular]`: approximate a Split View / Slide Over window for
        // screenshots (simctl can't resize the simulator's scene).
        if let w = Self.diagWidth {
            HStack(spacing: 0) {
                replay
                    .frame(width: w.width)
                    .environment(\.horizontalSizeClass, w.compact ? .compact : .regular)
                Rectangle().fill(Color.black).ignoresSafeArea()
            }
        } else {
            replay
        }
    }

    private static var diagWidth: (width: CGFloat, compact: Bool)? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-UMDiagWidth"), args.indices.contains(i + 1),
              let w = Double(args[i + 1]) else { return nil }
        let compact = args.indices.contains(i + 2) ? args[i + 2] == "compact" : w < 600
        return (CGFloat(w), compact)
    }

    /// `-UMDiagPregame spectator|seated`: a pregame lobby for the seat actions and text effects
    /// (site PRs #3053, #3093, #3090), no network.
    private static var diagPregame: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-UMDiagPregame") else { return nil }
        return args.indices.contains(i + 1) ? args[i + 1] : "spectator"
    }

    @MainActor
    private func runPregame(_ mode: String) async {
        let watching = mode != "seated"
        let s = GameSession(gameId: "diag-pregame", spectate: watching)
        app.game = s
        UMTextEffects.owned = true
        s.debugMarkConnected()
        s.debugFeed("options", ["spectating": true, "ranked": false])
        var players: [String: Any] = [:]
        let names = ["Vinman", "Pranay", "Rivka", "Ozzie", "Juno", "Basil"]
        for (i, n) in names.enumerated() {
            players["p\(i)"] = ["id": "p\(i)", "name": n, "avatar": false, "playerListPosition": i]
        }
        s.debugFeed("players", players)
        s.debugFeed("self", watching ? "s0" : "p0")
        s.debugFeed("state", ["id": -1, "name": "Pregame"])
        s.debugFeed("meeting", ["id": "pregame", "name": "Pregame", "speech": true, "voting": false,
                                "amMember": true, "canTalk": true])
        s.debugFeed("spectators", [
            "s0": ["id": "s0", "name": watching ? "Watcher" : "Watcher", "avatar": false, "watching": true],
            "s1": ["id": "s1", "name": "Marlowe", "avatar": false, "watching": true],
            "s9": ["id": "s9", "name": "Gone", "avatar": false],
        ])
        s.debugFeed("spectatorCount", 2)
        if watching { s.debugFeed("isSpectator", nil) }
        let now = Date().timeIntervalSince1970 * 1000
        func say(_ id: String, _ from: String, _ text: String, _ ago: Double, effect: String? = nil) {
            var m: [String: Any] = ["id": id, "senderId": from, "content": text, "time": now - ago * 1000,
                                    "meetingId": "pregame"]
            if let effect { m["textEffect"] = effect }
            s.debugFeed("message", m)
        }
        say("a1", "p1", "gl everyone, two more and we start", 40)
        say("a2", "s1", "watching this one, good luck", 30)
        say("a3", "p2", "hello table", 2, effect: "wave")
        if watching {
            s.debugFeed("message", ["id": "h1", "senderId": "server", "time": now - 1000,
                                    "content": ":system: You are spectating. Type /join to take a seat at the table."])
            s.debugFeed("takeSeatFailed", "No open seats.")
        } else {
            s.debugFeed("message", ["id": "h2", "senderId": "server", "time": now - 1000,
                                    "content": "Marlowe is now spectating."])
        }
        // Keep the text effects going for the snapshot: one fresh effect every second.
        for (k, e) in ["rainbow", "glow", "shake", "slide", "flash"].enumerated() {
            try? await Task.sleep(for: .milliseconds(900))
            say("fx\(k)", "p\(3 + k % 3)", "\(e) text effect demo", 0, effect: e)
        }
    }

    @MainActor
    private func run() async {
        if let mode = Self.diagPregame { await runPregame(mode); return }
        let s = GameSession(gameId: "diag-replay", spectate: true)
        app.game = s
        UMDiag.log("replay", "start")
        var players: [String: Any] = [:]
        for i in 0..<12 {
            players["p\(i)"] = ["id": "p\(i)", "name": "Player\(i)", "avatar": false, "playerListPosition": i]
        }
        s.debugFeed("loaded", nil)
        s.debugFeed("players", players)
        func msg(_ n: Int, phase: Int) -> [String: Any] {
            ["id": "m\(phase)-\(n)", "senderId": "p\(n % 12)", "content": "message \(n) in phase \(phase) about the cop and mafia vig claims",
             "time": Date().timeIntervalSince1970 * 1000, "meetingId": "village"]
        }
        if ProcessInfo.processInfo.arguments.contains("-UMDiagHistory") {
            // Joining a running game: the screen is up (empty) first, then the whole backlog arrives
            // in one `history` event, then `state`.
            try? await Task.sleep(for: .seconds(1.5))
            var states: [String: Any] = [:]
            for (phase, name) in [(0, "Day"), (1, "Night"), (2, "Day")] {
                var msgs: [[String: Any]] = []
                for n in 0..<(phase == 1 ? 20 : 150) {
                    var m = msg(n, phase: phase)
                    // Mixed row heights, like real chat (short lines and long paragraphs).
                    if n % 7 == 0 { m["content"] = String(repeating: "long claim about the cop and the vig and who to lynch today ", count: 1 + n % 4) }
                    msgs.append(m)
                }
                states["\(phase)"] = ["name": name, "dayCount": phase / 2 + 1,
                                      "meetings": ["village": ["id": "village", "name": "Village", "messages": msgs]]]
            }
            s.debugFeed("history", states)
            s.debugFeed("state", ["id": 2, "name": "Day", "dayCount": 2])
            // Then the meetings, one `meeting` event each (village first, then the Spectator Meeting,
            // which brings up the composer and changes the chat's bottom inset).
            s.debugFeed("meeting", ["id": "village", "name": "Village", "speech": true, "voting": true, "amMember": false,
                                    "canTalk": false, "targets": [String](), "votes": [String: Any]()])
            s.debugFeed("meeting", ["id": "spec", "name": "Spectator Meeting", "speech": true, "voting": false,
                                    "amMember": true, "canTalk": true])
            s.debugFeed("loaded", nil)
            UMDiag.log("replay", "history loaded")
            return
        }
        s.debugFeed("state", ["id": 0, "name": "Day", "dayCount": 1])
        for n in 0..<200 { s.debugFeed("message", msg(n, phase: 0)) }
        try? await Task.sleep(for: .seconds(3))
        UMDiag.log("replay", "-> night")
        s.debugFeed("state", ["id": 1, "name": "Night", "dayCount": 1])
        for n in 0..<10 {
            s.debugFeed("message", msg(n, phase: 1)); try? await Task.sleep(for: .milliseconds(200))
        }
        try? await Task.sleep(for: .seconds(2))
        UMDiag.log("replay", "-> day")
        s.debugFeed("state", ["id": 2, "name": "Day", "dayCount": 2])
        s.debugFeed("obituaries", ["source": "Night", "dayCount": 2, "time": Date().timeIntervalSince1970 * 1000,
                                   "obituaries": [["playerInfo": ["id": "p3", "name": "Player3"],
                                                   "snippets": ["deathMessage": "Player3 was found dead.", "revealMessage": "Player3's role is Villager."]]]])
        for n in 0..<30 {
            UMDiag.log("replay", "send m2-\(n)")
            s.debugFeed("message", msg(n, phase: 2)); try? await Task.sleep(for: .milliseconds(250))
        }
        for (i, t) in ["An Alien followed by a long sentence that should wrap across the whole paragraph",
                       "Player5 claimed Cop, but I think the Alien probed them last night and the Mafia will hit the Doctor next, so watch the votes"].enumerated() {
            s.debugFeed("message", ["id": "wrap\(i)", "senderId": "p\(4 + i)", "content": t,
                                    "time": Date().timeIntervalSince1970 * 1000, "meetingId": "village"])
        }
        UMDiag.log("replay", "done")
    }
}
#endif
