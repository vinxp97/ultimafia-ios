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

    var body: some View {
        ZStack {
            TabView {
                LobbyView()
                    .tabItem { Label("Play", systemImage: "theatermasks") }
                    .badge(app.seatedGameId == nil ? 0 : 1)
                    .toolbar(app.hideAppTabs ? .hidden : .automatic, for: .tabBar)
                ProfileView()
                    .tabItem { Label("You", systemImage: "person") }
                    .toolbar(app.hideAppTabs ? .hidden : .automatic, for: .tabBar)
            }
            .toolbarBackground(UMTheme.card, for: .tabBar)

            if let session = app.game {
                ReadyCheckOverlay(session: session, onLeave: { app.leaveActiveGame() })
                RoleRevealOverlay(session: session)
                if !app.hideAppTabs && !app.path.isEmpty && !app.showLeaveConfirm {
                    LeaveGameButton {
                        if session.leaveNeedsConfirm { app.showLeaveConfirm = true } else { app.leaveActiveGame() }
                    }
                }
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
