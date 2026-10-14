import ActivityKit
import SwiftUI
import WidgetKit

private let blood = Color(red: 0.78, green: 0.13, blue: 0.13)
private let kickRed = Color(red: 0.93, green: 0.2, blue: 0.2)
private let dayGold = Color(red: 0.98, green: 0.78, blue: 0.25)
private let nightBlue = Color(red: 0.55, green: 0.65, blue: 1.0)

struct GameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UMGameActivityAttributes.self) { context in
            GameActivityLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseLabel(state: s).font(.headline).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ClockRing(state: s, lineWidth: 4)
                        .frame(width: 40, height: 40)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.setupName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if s.atKicks {
                            Label("At kicks", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(kickRed)
                        }
                        Spacer()
                        CountdownText(state: s)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(s.atKicks ? kickRed : .white)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                PhaseIcon(state: s)
            } compactTrailing: {
                HStack(spacing: 4) {
                    CountdownText(state: s)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(s.atKicks ? kickRed : .white)
                        .frame(maxWidth: 40)
                    ClockRing(state: s, lineWidth: 2.5)
                        .frame(width: 16, height: 16)
                }
            } minimal: {
                ClockRing(state: s, lineWidth: 2.5).padding(2)
            }
            .keylineTint(s.atKicks ? kickRed : blood)
        }
    }
}

struct GameActivityLockScreenView: View {
    let attributes: UMGameActivityAttributes
    let state: UMGameActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ClockRing(state: state, lineWidth: 5)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                PhaseLabel(state: state).font(.headline)
                Text(attributes.setupName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if state.atKicks {
                    Text("At kicks")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(kickRed)
                }
            }
            Spacer()
            CountdownText(state: state)
                .font(.title.weight(.semibold).monospacedDigit())
                .foregroundStyle(state.atKicks ? kickRed : .white)
                .frame(maxWidth: 110, alignment: .trailing)
        }
        .padding(16)
    }
}

private struct PhaseIcon: View {
    let state: UMGameActivityAttributes.ContentState
    var body: some View {
        Image(systemName: state.isNight ? "moon.fill" : "sun.max.fill")
            .foregroundStyle(state.isNight ? nightBlue : dayGold)
    }
}

private struct PhaseLabel: View {
    let state: UMGameActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 6) {
            PhaseIcon(state: state)
            Text(state.phaseName).foregroundStyle(.white)
        }
    }
}

/// Counts down by itself from the phase end date.
private struct CountdownText: View {
    let state: UMGameActivityAttributes.ContentState
    var body: some View {
        if let end = state.clockEnd, end > Date() {
            Text(timerInterval: (state.clockStart ?? Date())...end, countsDown: true)
                .multilineTextAlignment(.trailing)
        } else {
            Text("--:--")
        }
    }
}

/// Circular time-remaining ring; dotted red at kicks.
private struct ClockRing: View {
    let state: UMGameActivityAttributes.ContentState
    var lineWidth: CGFloat

    var body: some View {
        let color = state.atKicks ? kickRed : (state.isNight ? nightBlue : dayGold)
        ZStack {
            Circle()
                .stroke(color.opacity(state.atKicks ? 0.9 : 0.25),
                        style: StrokeStyle(lineWidth: lineWidth, dash: state.atKicks ? [2, 3] : []))
            if let end = state.clockEnd, let start = state.clockStart, end > Date(), start < end {
                ProgressView(timerInterval: start...end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(color)
            }
        }
    }
}

#Preview("Lock Screen", as: .content, using: UMGameActivityAttributes(gameId: "x", setupName: "Classic 7")) {
    GameLiveActivity()
} contentStates: {
    UMGameActivityAttributes.ContentState(phaseName: "Day 2", isNight: false, clockStart: .now, clockEnd: .now + 300, atKicks: false)
    UMGameActivityAttributes.ContentState(phaseName: "Day 3", isNight: false, clockStart: .now, clockEnd: .now + 60, atKicks: true)
}
