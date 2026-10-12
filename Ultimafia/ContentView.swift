import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if app.isRestoring {
                ZStack {
                    UMTheme.bg.ignoresSafeArea()
                    ProgressView().tint(UMTheme.blood)
                }
            } else if app.isSignedIn {
                MainTabs()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(.dark)
        .task {
            ReadyNotifications.requestPermission()
            await app.bootstrap()
        }
        .task {
            await RoleCatalog.shared.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                if app.game != nil { GameBackgroundHold.start() }
                app.stopPresence()
            } else if phase == .active {
                GameBackgroundHold.end()
                app.startPresence()
            }
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var app
    @State private var tab = "play"
    @State private var keyboardShown = false

    private enum BarItem: String { case leave, lobby, game, create, you }

    /// Stable buttons: seated -> Leave, Lobby, Game, You; otherwise Lobby, Create, You.
    private var items: [BarItem] {
        app.seatedGameId != nil ? [.leave, .lobby, .game, .you] : [.lobby, .create, .you]
    }

    private var selected: BarItem {
        if tab == "you" { return .you }
        return app.isOnGameScreen ? .game : .lobby
    }

    private func tap(_ item: BarItem) {
        switch item {
        case .leave:
            if let session = app.game {
                if session.leaveNeedsConfirm { app.showLeaveConfirm = true } else { app.leaveActiveGame() }
            }
        case .lobby:
            tab = "play"
            if !app.path.isEmpty { app.goToLobby() } else { app.lobbyScrollToTop += 1 }
        case .game:
            let fromYou = tab == "you"
            tab = "play"
            // Back from You onto a game screen that's still on the stack: just switch, no collapse.
            if fromYou, app.isOnGameScreen { return }
            if !app.isOnGameScreen { app.resumeSeatedGame() }
        case .create:
            tab = "play"
            app.openCreate()
        case .you:
            if tab == "play", app.isOnProfile { app.dropProfiles() }
            tab = "you"
        }
    }

    private func info(_ item: BarItem) -> (String, String) {
        switch item {
        case .leave: ("Leave", "arrow.left")
        case .lobby: ("Lobby", "list.bullet.rectangle")
        case .game: ("Game", "gamecontroller")
        case .create: ("Create", "plus.circle")
        case .you: ("You", "person")
        }
    }

    /// `hideAppTabs` = app bar collapsed; it only applies on the game screen (Play tab).
    private var showBar: Bool {
        if keyboardShown { return false }
        if tab == "you" { return true }
        if app.suppressAppBar { return false }
        return !app.hideAppTabs || !app.isOnCollapsibleGameScreen
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let (title, icon) = info(item)
                let on = item == selected
                Button { tap(item) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: icon).font(.system(size: 20))
                            .overlay(alignment: .topTrailing) {
                                if item == .game, app.mentionBadge > 0 {
                                    Text("\(app.mentionBadge)")
                                        .font(.caption2.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Capsule().fill(.red))
                                        .offset(x: 12, y: -6)
                                }
                            }
                        Text(title).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6).padding(.bottom, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .background(UMTheme.card.ignoresSafeArea(edges: .bottom))
    }

    var body: some View {
        ZStack {
            // A real stack (not a safe-area inset) so screens end above the bar and their own
            // bottom rows (e.g. the in-game picker) are never covered by it.
            VStack(spacing: 0) {
                TabView(selection: $tab) {
                    LobbyView()
                        .tag("play")
                        .toolbar(.hidden, for: .tabBar)
                    ProfileView()
                        .tag("you")
                        .toolbar(.hidden, for: .tabBar)
                }
                if showBar {
                    bar.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.28), value: showBar)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }

            if let session = app.game {
                ReadyCheckOverlay(session: session, onLeave: { app.leaveActiveGame() })
                RoleRevealOverlay(session: session)
                if app.showLeaveConfirm {
                    LeaveConfirmOverlay(
                        warning: session.participationRequired
                            ? ((session.rankedGame || session.competitiveGame)
                               ? "YOU WILL BE PENALISED FOR LEAVING" : "Your participation is still required")
                            : nil,
                        lockSeconds: session.participationRequired ? 5 : 0,
                        onStay: { app.showLeaveConfirm = false },
                        onLeave: {
                            app.showLeaveConfirm = false
                            app.leaveActiveGame()
                        }
                    )
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
