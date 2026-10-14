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
        // Round to whole seconds so small clock jitter doesn't trigger updates.
        func r(_ d: Date?) -> Date? { d.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded()) } }
        return .init(phaseName: phase, isNight: isNight, clockStart: r(start), clockEnd: r(end), atKicks: atKicks)
    }

    static func start(session: GameSession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.info("live activities disabled")
            return
        }
        guard session.isGameInProgress, !session.isReview else { return }
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
                if session.finished || !session.isGameInProgress {
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
