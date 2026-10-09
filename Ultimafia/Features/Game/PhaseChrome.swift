import SwiftUI

struct PhaseBar: View {
    var session: GameSession

    var body: some View {
        let phases = session.sortedPhases
        HStack(spacing: 4) {
            Button {
                session.viewAdjacentPhase(delta: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .frame(width: 32, height: 32)
            }
            .disabled(phases.first?.id == session.viewingPhaseId)
            .foregroundStyle(phases.first?.id == session.viewingPhaseId ? UMTheme.muted : .white)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(phases) { phase in
                            Button {
                                session.viewPhase(phase.id)
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: icon(for: phase.name))
                                        .font(.title3)
                                        .foregroundStyle(phase.id == session.viewingPhaseId ? UMTheme.blood : UMTheme.muted)
                                        .frame(width: 32, height: 28)
                                    Text(shortLabel(phase))
                                        .font(.caption2.weight(phase.id == session.viewingPhaseId ? .bold : .regular))
                                        .foregroundStyle(phase.id == session.viewingPhaseId ? .white : UMTheme.muted)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .id(phase.id)
                            .opacity(phase.id == session.viewingPhaseId ? 1 : 0.55)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onChange(of: session.viewingPhaseId) { _, id in
                    proxy.scrollTo(id, anchor: .center)
                }
            }

            Button {
                session.viewAdjacentPhase(delta: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .frame(width: 32, height: 32)
            }
            .disabled(phases.last?.id == session.viewingPhaseId)
            .foregroundStyle(phases.last?.id == session.viewingPhaseId ? UMTheme.muted : .white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(UMTheme.card)
    }

    private func icon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("pregame") { return "house.fill" }
        if n.contains("night") { return "moon.fill" }
        if n.contains("day") { return "sun.max.fill" }
        if n.contains("dawn") { return "sunrise.fill" }
        if n.contains("dusk") { return "sunset.fill" }
        if n.contains("post") { return "flag.checkered" }
        return "circle.fill"
    }

    private func shortLabel(_ phase: GamePhase) -> String {
        let n = phase.name
        if let day = phase.dayCount, n == "Day" || n == "Night" {
            return "\(n) \(day)"
        }
        if n.lowercased() == "pregame" { return "Pre" }
        return n
    }
}

struct RoleRevealOverlay: View {
    var session: GameSession

    var body: some View {
        if session.showRoleReveal, let role = session.selfRoleName {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("Your role is")
                        .font(.subheadline)
                        .foregroundStyle(UMTheme.muted)
                    Text(role)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(UMTheme.blood)
                    if !session.selfRoleModifiers.isEmpty {
                        Text(session.selfRoleModifiers.joined(separator: " / "))
                            .font(.caption)
                            .foregroundStyle(UMTheme.muted)
                    }
                    if let cat = session.selfRoleCategory {
                        Text(cat)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(UMTheme.muted)
                    }
                    if !session.teammates.isEmpty {
                        VStack(spacing: 8) {
                            Text("Your teammates")
                                .font(.subheadline.weight(.semibold))
                            ForEach(session.teammates) { mate in
                                HStack(spacing: 8) {
                                    UMAvatarView(player: mate, size: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        PlayerNameView(player: mate, fontSize: 16, dead: session.isDead(mate.id))
                                        if let r = session.knownRoles[mate.id] {
                                            Text(r.split(separator: ":").first.map(String.init) ?? r)
                                                .font(.caption2)
                                                .foregroundStyle(UMTheme.muted)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    Button("OK") {
                        session.showRoleReveal = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(UMTheme.blood)
                    .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: 360)
                .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 18))
                .padding(28)
            }
        }
    }
}

struct TypingStrip: View {
    var session: GameSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Color.clear
                        .frame(width: 1, height: 22)
                        .id("typing-start")
                    ForEach(session.typingPlayers) { player in
                        HStack(spacing: 4) {
                            UMAvatarView(player: player, size: 22)
                            PulsingDots()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(UMTheme.card, in: Capsule())
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
            .background(UMTheme.elevated)
            .onChange(of: session.typingPlayerIds) { old, ids in
                if ids.isEmpty || ids.count < old.count {
                    proxy.scrollTo("typing-start", anchor: .leading)
                }
            }
        }
    }
}

struct PulsingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    let wave = (sin(t * 5.5 + Double(i) * 0.7) + 1) / 2
                    Circle()
                        .fill(.white.opacity(0.35 + 0.65 * wave))
                        .frame(width: 5, height: 5)
                        .offset(y: -2.5 * wave)
                }
            }
            .frame(width: 22, height: 12)
        }
    }
}


struct PhaseTimerBadge: View {
    var session: GameSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let kind = session.clockKind
            let text = format(session.clockRemainingMs(at: context.date))
            Text(text)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(foreground(kind))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(UMTheme.elevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(border(kind), style: StrokeStyle(lineWidth: 1.5, dash: dashes(kind)))
                )
        }
    }

    private func format(_ ms: Double?) -> String {
        guard let ms else { return "--:--" }
        let total = max(0, Int((ms / 1000).rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func foreground(_ kind: ClockKind) -> Color {
        switch kind {
        case .vegKick, .vegKickCountdown: return UMTheme.mafia
        case .secondary: return Color(red: 0.93, green: 0.54, blue: 0.05)
        case .normal: return .white
        }
    }

    private func border(_ kind: ClockKind) -> Color {
        switch kind {
        case .vegKick, .vegKickCountdown: return UMTheme.mafia
        case .secondary: return Color(red: 0.93, green: 0.54, blue: 0.05)
        case .normal: return UMTheme.line
        }
    }

    private func dashes(_ kind: ClockKind) -> [CGFloat] {
        switch kind {
        case .secondary, .vegKickCountdown: return [5, 3]
        default: return []
        }
    }
}
