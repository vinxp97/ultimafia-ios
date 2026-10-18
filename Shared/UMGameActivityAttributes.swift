// Live Activities don't exist on Mac (Catalyst): compiled for iPhone/iPad and the widget only.
#if !targetEnvironment(macCatalyst)
import ActivityKit
import Foundation

/// Live Activity for a game in progress (Dynamic Island + Lock Screen). Shared by the app (which
/// starts/updates/ends it) and the UltimafiaWidgets extension (which draws it).
nonisolated struct UMGameActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// "Day 2", "Night 1", "Pregame"...
        var phaseName: String
        var isNight: Bool
        /// When the running clock started and ends. The views count down from these by themselves
        /// (Text(timerInterval:) / ProgressView(timerInterval:)), so no per-second updates are needed.
        var clockStart: Date?
        var clockEnd: Date?
        /// At kicks (vegKick / vegKickCountdown clock running): the ring turns dotted red.
        var atKicks: Bool
        /// "phase" (day/night), "pregame" (house icon) or "ready" (ready check: ringing bell,
        /// clock = ready-check countdown).
        var stage: String = "phase"

        var isPregame: Bool { stage == "pregame" }
        var isReadyCheck: Bool { stage == "ready" }
    }

    var gameId: String
    var setupName: String
}
#endif
