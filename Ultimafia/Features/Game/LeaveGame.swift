import SwiftUI

/// Small round back-arrow shown left of the Play/You bar while in a game.
struct LeaveGameButton: View {
    var action: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Button(action: action) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(UMTheme.mafia)
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Leave game")
                Spacer()
            }
            .padding(.leading, 20)
            .padding(.bottom, 6)
        }
        .ignoresSafeArea(.keyboard)
    }
}

/// Confirm sheet styled like the ready check. In-progress games lock Leave for 5s.
struct LeaveConfirmOverlay: View {
    var inProgress: Bool
    var onStay: () -> Void
    var onLeave: () -> Void
    @State private var unlockAt = Date()

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onStay)
            VStack(spacing: 16) {
                Text("Leave Game?")
                    .font(.title2.weight(.bold))
                Text(inProgress
                     ? "This game is in progress. If you leave, you may be penalized."
                     : "Are you sure you want to leave this game?")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                TimelineView(.periodic(from: .now, by: 0.2)) { context in
                    let left = max(0, unlockAt.timeIntervalSince(context.date))
                    HStack(spacing: 12) {
                        Button("Stay", action: onStay)
                            .buttonStyle(.borderedProminent)
                            .tint(UMTheme.village)
                        Button(role: .destructive, action: onLeave) {
                            Text(left > 0 ? "Leave (\(Int(left.rounded(.up))))" : "Leave")
                                .monospacedDigit()
                        }
                        .buttonStyle(.bordered)
                        .disabled(left > 0)
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 18))
            .padding(28)
        }
        .onAppear { unlockAt = inProgress ? Date().addingTimeInterval(5) : Date() }
    }
}
