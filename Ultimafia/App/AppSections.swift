import SwiftUI

/// The Game section: the live game, or a plain explanation when there isn't one. Apple's
/// guidance for an empty tab is to say why it is empty rather than hide it.
struct GameSectionView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.gamePath) {
            Group {
                if app.game != nil {
                    GameView()
                } else {
                    UMNotInGameView()
                }
            }
            .navigationDestination(for: AppModel.Route.self) { SectionRouteView(route: $0) }
        }
    }
}

/// Destinations the non-Play sections can push. Reviews belong to the Play stack, so they are
/// not reachable from here.
struct SectionRouteView: View {
    var route: AppModel.Route

    var body: some View {
        switch route {
        case .profile(let id, let name):
            UserProfileView(userId: id, userName: name)
        case .family(let id, let name):
            FamilyView(familyId: id, familyName: name)
        case .review:
            EmptyView()
        case .host:
            SetupSearchView()
        }
    }
}

struct UMNotInGameView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 42))
                .foregroundStyle(UMTheme.muted)
            Text("You're not in a game")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Join or host a game from the lobby and it will open here.")
                .font(.subheadline)
                .foregroundStyle(UMTheme.muted)
                .multilineTextAlignment(.center)
            Button("Browse open games") { app.select(.play) }
                .buttonStyle(.borderedProminent)
                .tint(UMTheme.blood)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UMTheme.bg.ignoresSafeArea())
    }
}
