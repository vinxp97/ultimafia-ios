import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UMDiagReplay") {
                DiagReplayView()
            } else if app.isRestoring {
                ZStack {
                    UMTheme.bg.ignoresSafeArea()
                    ProgressView().tint(UMTheme.blood)
                }
            } else if app.isSignedIn {
                MainTabs()
            } else {
                LoginView()
            }
            #else
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
            #endif
        }
        .preferredColorScheme(.dark)
        .task {
            ReadyNotifications.requestPermission()
            await app.bootstrap()
        }
        .task {
            await RoleCatalog.shared.load()
        }
        .task {
            await UMTerminology.shared.load()
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
            // Sections, always present in this order. UIKit owns the bar, so selection, Liquid
            // Glass and safe areas behave the way the system does; nothing here hides or reorders
            // an item, and only a live game takes the bar away. Hosting is a screen inside the
            // lobby rather than a section of its own, matching the website.
            NativeAppTabs(
                selected: app.section,
                mentionBadge: app.mentionBadge,
                showsBar: app.showsAppTabs,
                play: AnyView(LobbyView().environment(app)),
                game: AnyView(GameSectionView().environment(app)),
                you: AnyView(ProfileView().environment(app)),
                onSelect: { app.select($0) }
            )
            .ignoresSafeArea()
            // Signed-in shell settled: warm Z's profile (credits link) at low priority.
            .task {
                try? await Task.sleep(for: .seconds(8))
                let ids = AccountStore.shared.accounts.map(\.id)
                await Task.detached(priority: .background) {
                    await UMProfileCache.prefetchAll(accountIds: ids)
                }.value
            }

            if let session = app.game {
                // The ready-check overlay's Leave is a leave like any other: it goes through the
                // same confirmation rule instead of ending a live game outright.
                ReadyCheckOverlay(session: session, onLeave: { app.requestLeave() })
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
        .alert("Ultimafia", isPresented: alertPresented) {
            Button("OK", role: .cancel) { app.alertMessage = nil }
        } message: {
            Text(app.alertMessage ?? "")
        }
    }

    /// A refused action is reported once, wherever the user is in the shell.
    private var alertPresented: Binding<Bool> {
        Binding(
            get: { app.alertMessage != nil },
            set: { if !$0 { app.alertMessage = nil } }
        )
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
