import SwiftUI

struct LobbyView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    playHeader
                    onlineStrip
                    if app.isOnLobbyWhileSeated {
                        seatedBanner
                    }
                    section("Open", games: excludingSeated(app.openGames), empty: "No open games right now.")
                    section("In progress", games: excludingSeated(app.inProgressGames), empty: "Nothing in progress.")
                    section("Finished", games: app.finishedGames, empty: "No finished games.")
                    if app.finishedHasMore, !app.finishedGames.isEmpty {
                        Button("Load more") { Task { await app.loadFinished(reset: false) } }
                            .frame(maxWidth: .infinity)
                            .tint(UMTheme.blood)
                    }
                }
                .padding(16)
            }
            .pointerScrolling()
            .background(UMTheme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await app.refreshLobby() }
            .task {
                await RoleCatalog.shared.load()
                await app.refreshLobby()
                app.startPresence()
            }
            .fullScreenCover(item: Bindable(app).reviewItem) { item in
                UMInAppBrowser(url: item.url, shareSiteSession: true) { app.reviewItem = nil }
            }
            .navigationDestination(for: AppModel.Route.self) { route in
                switch route {
                case .game:
                    GameView()
                case .profile(let id, let name):
                    UserProfileView(userId: id, userName: name)
                case .setupSearch:
                    SetupSearchView()
                }
            }
        }
    }

    private var playHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Ultimafia Mobile")
                .font(.largeTitle.weight(.bold))
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                Task { await app.refreshLobby() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(UMTheme.muted)
            }
            .buttonStyle(.plain)
        }
    }

    private var onlineStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(app.onlineUsers.count) Players online:")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(app.onlineUsers) { person in
                        Button {
                            let key = (person.vanityUrl?.isEmpty == false) ? person.vanityUrl! : person.id
                            app.openProfile(id: key, name: person.name ?? "")
                        } label: {
                            VStack(spacing: 4) {
                                UMAvatarView(
                                    userId: person.id,
                                    hasAvatar: person.avatar ?? false,
                                    name: person.name ?? "",
                                    size: 48
                                )
                                Text(person.name ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(UMTheme.muted)
                                    .lineLimit(1)
                                    .frame(width: 56)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// The seated game is pinned in the banner up top, so don't list it again below.
    private func excludingSeated(_ games: [GameSummary]) -> [GameSummary] {
        guard app.isOnLobbyWhileSeated, let id = app.seatedGameId else { return games }
        return games.filter { $0.id != id }
    }

    private var seatedBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOU'RE IN A GAME")
                .font(.caption.weight(.bold))
                .foregroundStyle(UMTheme.blood)
            Text(UMText.clipped(app.seatedSetupName))
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(app.seatedPhaseLabel)
                if let extra = app.seatedPlayerLabel {
                    Text("·")
                    Text(extra)
                }
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(UMTheme.muted)
            seatedRoleStrip
            HStack(spacing: 10) {
                Button("Return to Game") { app.resumeSeatedGame() }
                    .buttonStyle(.borderedProminent)
                    .tint(UMTheme.blood)
                Button("Leave Game", role: .destructive) { app.leaveActiveGame() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UMTheme.blood.opacity(0.55)))
    }

    @ViewBuilder
    private var seatedRoleStrip: some View {
        if let session = app.game, !session.setupRoles.isEmpty || !session.setupBanished.isEmpty {
            SetupPreviewStrip(
                gameType: session.setupGameType,
                rolesets: session.setupRolesets,
                banished: session.setupBanished,
                isSimpleMulti: session.isSimpleMulti,
                displayedRoles: session.setupRoles,
                onCycle: { session.cycleSetupRoleset() },
                compact: true
            )
        } else if let setup = app.seatedGameSummary?.setup {
            LobbySetupStrip(setup: setup, gameType: app.seatedGameSummary?.type ?? "Mafia")
        }
    }

    private func section(_ title: String, games: [GameSummary], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(UMTheme.muted)
            if games.isEmpty {
                Text(empty)
                    .foregroundStyle(UMTheme.muted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 14))
            } else {
                ForEach(games) { game in
                    GameRow(game: game)
                }
            }
        }
    }
}

struct GameRow: View {
    @Environment(AppModel.self) private var app
    let game: GameSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(game.type ?? "Game")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(UMTheme.blood)
                if game.ranked == true {
                    tag("Ranked", UMTheme.mafia)
                }
                if game.competitive == true {
                    tag("Comp", Color.yellow)
                }
                Spacer()
                Text("\(game.playerCount)/\(game.setupTotal)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            Text(game.setup?.clippedName ?? "Custom setup")
                .font(.headline)
                .lineLimit(1)
            if let setup = game.setup {
                LobbySetupStrip(setup: setup, gameType: game.type ?? "Mafia")
            }
            HStack {
                Text(game.lobbyName ?? game.lobby ?? "")
                    .foregroundStyle(UMTheme.muted)
                    .font(.caption)
                Spacer()
                if game.id == app.seatedGameId {
                    Button("Return") { app.resumeSeatedGame() }
                        .buttonStyle(.borderedProminent)
                        .tint(UMTheme.blood)
                    Button("Leave Game", role: .destructive) { app.leaveActiveGame() }
                        .buttonStyle(.bordered)
                } else if game.isOpen {
                    Button("Join") { app.openGame(game) }
                        .buttonStyle(.borderedProminent)
                        .tint(UMTheme.blood)
                    if game.spectating == true {
                        Button("Watch") { app.openGame(game, spectate: true) }
                            .buttonStyle(.bordered)
                    }
                } else if game.isFinished {
                    Button("Review") { app.reviewItem = UMBrowserItem(url: game.reviewURL) }
                        .buttonStyle(.bordered)
                } else {
                    Button("Spectate") { app.openGame(game, spectate: true) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UMTheme.line))
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}

struct LobbySetupStrip: View {
    var setup: SetupInfo
    var gameType: String

    var body: some View {
        let bundle = setup.roleBundle(defaultGameType: gameType)
        SetupPreviewStrip(
            gameType: setup.gameType ?? gameType,
            rolesets: bundle.rolesets,
            banished: bundle.banished,
            isSimpleMulti: setup.isSimpleMulti(defaultGameType: gameType),
            compact: true
        )
    }
}
