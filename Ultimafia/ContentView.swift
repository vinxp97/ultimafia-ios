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

    /// Leave lives in the tab bar as a fake tab: selecting it pops the confirm and snaps back.
    private var tabSelection: Binding<String> {
        Binding(
            get: { tab },
            set: { new in
                if new == "play", tab == "play" { app.playTabReselected(); return }
                guard new == "leave" else { tab = new; return }
                if let session = app.game {
                    if session.leaveNeedsConfirm { app.showLeaveConfirm = true } else { app.leaveActiveGame() }
                }
            }
        )
    }

    private var playLabel: (title: String, icon: String) {
        guard app.seatedGameId != nil else { return ("Play", "theatermasks") }
        return app.isOnGameScreen ? ("Lobby", "list.bullet.rectangle") : ("Game", "gamecontroller")
    }

    var body: some View {
        ZStack {
            TabView(selection: tabSelection) {
                if app.game != nil {
                    Color.clear
                        .tabItem { Label("Leave", systemImage: "arrow.left") }
                        .tag("leave")
                        .toolbar(app.hideAppTabs ? .hidden : .automatic, for: .tabBar)
                }
                LobbyView()
                    .tabItem { Label(playLabel.title, systemImage: playLabel.icon) }
                    .tag("play")
                    .badge(app.seatedGameId == nil ? 0 : 1)
                    .toolbar(app.hideAppTabs ? .hidden : .automatic, for: .tabBar)
                ProfileView()
                    .tabItem { Label("You", systemImage: "person") }
                    .tag("you")
                    .toolbar(app.hideAppTabs ? .hidden : .automatic, for: .tabBar)
            }
            .toolbarBackground(UMTheme.card, for: .tabBar)

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
