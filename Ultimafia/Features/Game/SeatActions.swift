import SwiftUI

/// Pregame seat actions (site PRs #3053 / #3093), the same pair the web shows under the chat:
/// a spectator gets "Join open seat" (`takeSeat`, the checks `/join` uses), a seated player in a
/// game that allows spectators gets "Spectate" (reopens as a spectator, like `?spectate=true`).
struct PregameSeatButton: View {
    @Environment(AppModel.self) private var app
    var session: GameSession
    /// Header capsule ("Join") instead of the chat bar's "Join open seat".
    var compact = true

    var body: some View {
        if session.canTakeSeat {
            Button { app.takeOpenSeat() } label: {
                Label(compact ? "Join" : "Join open seat", systemImage: "chair.fill")
                    .font((compact ? Font.caption : .subheadline).weight(.bold))
                    .padding(.horizontal, compact ? 10 : 14)
                    .padding(.vertical, compact ? 5 : 8)
                    .background(UMTheme.blood, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Take an open seat (/join)")
            .accessibilityLabel("Join open seat")
        } else if session.canSpectateFromSeat {
            Button { app.spectateFromSeat() } label: {
                Label("Spectate", systemImage: "eye")
                    .font((compact ? Font.caption : .subheadline).weight(.bold))
                    .padding(.horizontal, compact ? 10 : 14)
                    .padding(.vertical, compact ? 5 : 8)
                    .overlay(Capsule().stroke(UMTheme.line, lineWidth: 1))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Give up your seat and watch (/spectate)")
            .accessibilityLabel("Give up your seat and spectate")
        }
    }
}

/// Above the composer for a pregame spectator: what they are and how to sit down. Players never
/// see it.
struct PregameSpectatorBar: View {
    var session: GameSession

    var body: some View {
        if session.canTakeSeat {
            HStack(spacing: 10) {
                Label(session.missedReadyCheck ? "You didn't ready in time, so you're spectating."
                      : "You're spectating. Take a seat here or with /join.",
                      systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(UMTheme.muted)
                    .lineLimit(2)
                Spacer(minLength: 4)
                PregameSeatButton(session: session, compact: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(UMTheme.elevated)
        }
    }
}

/// Header eye count: how many are watching (players in a started game only get this, #3093).
struct SpectatorCountBadge: View {
    var session: GameSession

    var body: some View {
        if session.spectatorCount > 0, !session.isReview {
            Label("\(session.spectatorCount)", systemImage: "eye")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(UMTheme.muted)
                .labelStyle(.titleAndIcon)
                .help("\(session.spectatorCount) spectating")
                .accessibilityLabel("\(session.spectatorCount) spectating")
        }
    }
}
