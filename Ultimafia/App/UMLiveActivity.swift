import ActivityKit
import Foundation
import os

/// Starts the game Live Activity (Dynamic Island + Lock Screen) when the app goes to the background
/// during a game, updates it while the app is still running, and ends it on foreground or game end.
/// Local updates only: if iOS suspends the app, the countdown keeps running from the phase end date
/// but phase changes won't arrive until the app runs again (server ActivityKit pushes would need
/// server work).
@MainActor
enum UMLiveActivity {
    private static let log = Logger(subsystem: "VCCCLLC.Ultimafia", category: "LiveActivity")
    private static var activity: Activity<UMGameActivityAttributes>?
    private static var updateTask: Task<Void, Never>?
    private static var lastState: UMGameActivityAttributes.ContentState?

    static func state(for session: GameSession, now: Date = Date()) -> UMGameActivityAttributes.ContentState {
        func r(_ d: Date?) -> Date? { d.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded()) } }
        if session.currentPhaseId == -1 {
            let joined = session.players.count
            let total = session.setupRoles.reduce(0) { $0 + $1.count }
            let count = total > 0 ? "\(joined)/\(total) players" : (joined > 0 ? "\(joined) players" : "Pregame")
            if session.readyCheckActive {
                let end = session.readyEndTime
                // The ready check's full length isn't sent; keep the start from when it was first seen.
                let start = (lastState?.isReadyCheck == true ? lastState?.clockStart : nil) ?? r(now)
                return .init(phaseName: "Ready check", isNight: false,
                             clockStart: start, clockEnd: end > now ? r(end) : nil, atKicks: false, stage: "ready")
            }
            var start: Date?
            var end: Date?
            if let left = session.clockRemainingMs(at: now), left > 0 {
                end = now.addingTimeInterval(left / 1000)
                let total = session.clocks[session.activeClockName]?.delayMs ?? left
                start = end!.addingTimeInterval(-max(total, left) / 1000)
            }
            return .init(phaseName: count, isNight: false, clockStart: r(start), clockEnd: r(end),
                         atKicks: false, stage: "pregame")
        }
        let kind = session.clockKind
        let atKicks = kind == .vegKick || kind == .vegKickCountdown
        var start: Date?
        var end: Date?
        if let left = session.clockRemainingMs(at: now), left > 0 {
            end = now.addingTimeInterval(left / 1000)
            let total = session.clocks[session.activeClockName]?.delayMs ?? left
            start = end!.addingTimeInterval(-max(total, left) / 1000)
        }
        // Match the phase bar (PhaseChrome.icon): case-insensitive, so "night", "Night", "Night 2" all map to night.
        let raw = session.stateName.trimmingCharacters(in: .whitespaces)
        let lower = raw.lowercased()
        let isNight = lower.contains("night")
        let isDay = !isNight && lower.contains("day")
        let base = isNight ? "Night" : (isDay ? "Day" : raw)
        let phase: String
        if let day = session.dayCount, isNight || isDay {
            phase = "\(base) \(day)"
        } else {
            phase = base
        }
        return .init(phaseName: phase, isNight: isNight, clockStart: r(start), clockEnd: r(end), atKicks: atKicks)
    }

    /// Pregame (phase -1) counts too, so the activity can show the lobby wait and the ready check.
    private static func isLive(_ session: GameSession) -> Bool {
        !session.isReview && !session.finished && session.currentPhaseId >= -1
    }

    static func start(session: GameSession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.info("live activities disabled")
            return
        }
        guard isLive(session) else { return }
        endAll()
        let attrs = UMGameActivityAttributes(gameId: session.gameId,
                                             setupName: session.setupName ?? session.gameType ?? "Ultimafia")
        let st = state(for: session)
        do {
            activity = try Activity.request(attributes: attrs,
                                            content: .init(state: st, staleDate: st.clockEnd),
                                            pushType: nil)
            lastState = st
            log.info("started \(st.phaseName, privacy: .public)")
        } catch {
            log.error("start failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        updateTask = Task { @MainActor [weak session] in
            while !Task.isCancelled, let session {
                try? await Task.sleep(for: .seconds(2))
                if !isLive(session) {
                    endAll()
                    return
                }
                let st = state(for: session)
                if st != lastState, let activity = activity ?? Activity<UMGameActivityAttributes>.activities.first {
                    lastState = st
                    log.info("update \(st.phaseName, privacy: .public) night=\(st.isNight)")
                    await activity.update(.init(state: st, staleDate: st.clockEnd))
                }
            }
        }
    }

    static func endAll() {
        updateTask?.cancel()
        updateTask = nil
        activity = nil
        lastState = nil
        for a in Activity<UMGameActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
