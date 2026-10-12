import Foundation
import Observation

@Observable
final class AppModel {
    var user: UserInfo?
    var isRestoring = true
    var isBusy = false
    var errorMessage: String?
    var lobby = "Main"
    var openGames: [GameSummary] = []
    var inProgressGames: [GameSummary] = []
    var openCounts: [String: Int] = [:]
    var path: [Route] = []
    var game: GameSession?
    var hideAppTabs = false
    var showLeaveConfirm = false
    var onlineUsers: [OnlineUser] = []
    @ObservationIgnored private var presenceTask: Task<Void, Never>?

    enum Route: Hashable {
        case game(String, spectate: Bool)
        case profile(id: String, name: String)
    }

    var isSignedIn: Bool { user?.id != nil }

    var seatedGameId: String? {
        user?.inGameId ?? game?.gameId
    }

    var seatedGameSummary: GameSummary? {
        guard let id = seatedGameId else { return nil }
        return (openGames + inProgressGames).first { $0.id == id }
    }

    var seatedSetupName: String {
        if let name = game?.setupName, !name.isEmpty { return name }
        return seatedGameSummary?.setup?.name ?? "Game"
    }

    var seatedPhaseLabel: String {
        if let g = game {
            let n = g.stateName
            if n != "Connecting", !n.isEmpty {
                if let d = g.dayCount, n == "Day" || n == "Night" {
                    return "\(n) \(d)"
                }
                return n
            }
        }
        if let s = seatedGameSummary?.gameState, !s.isEmpty { return s }
        return "In progress"
    }

    var seatedPlayerLabel: String? {
        if let summary = seatedGameSummary, summary.setupTotal > 0 {
            return "\(summary.playerCount)/\(summary.setupTotal)"
        }
        if let g = game, !g.players.isEmpty {
            return "\(g.players.count) players"
        }
        return nil
    }

    var isOnLobbyWhileSeated: Bool {
        seatedGameId != nil && path.isEmpty
    }

    func bootstrap() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            let info = try await APIClient.shared.userInfo()
            if info.id != nil {
                user = info
                startPresence()
                await refreshLobby()
                resumeIfSeated()
            }
        } catch {
            user = nil
        }
    }

    func signIn(email: String, password: String, remember: Bool) async {
        await run {
            let token = try await FirebaseAuth.signIn(email: email, password: password)
            try await APIClient.shared.establishSession(idToken: token)
            let info = try await APIClient.shared.userInfo()
            guard info.id != nil else { throw UMError.message("Check your email to verify the account, then sign in.") }
            self.user = info
            self.startPresence()
            if remember {
                RememberedLogin.save(email: email, password: password)
            } else {
                RememberedLogin.clear()
            }
            await self.refreshLobby()
            self.resumeIfSeated()
        }
    }

    func signUp(email: String, password: String) async {
        await run {
            _ = try await FirebaseAuth.signUp(email: email, password: password)
            self.errorMessage = "Account created. Verify the email we sent, then sign in."
        }
    }

    func signOut() async {
        leaveActiveGame()
        stopPresence()
        await APIClient.shared.logout()
        user = nil
        onlineUsers = []
        openGames = []
        inProgressGames = []
        path = []
    }

    func refreshLobby() async {
        do {
            async let open = APIClient.shared.gameList(list: "open", lobby: lobby)
            async let progress = APIClient.shared.gameList(list: "in progress", lobby: lobby)
            async let counts = APIClient.shared.openCounts()
            async let online = APIClient.shared.onlineUsers()
            openGames = (try await open).filter(\.isOpen)
            inProgressGames = try await progress
            openCounts = (try await counts).countValues
            onlineUsers = (try? await online) ?? onlineUsers
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openGame(_ summary: GameSummary, spectate: Bool = false) {
        resumeGame(summary.id, spectate: spectate)
    }

    func resumeSeatedGame() {
        guard let id = seatedGameId else { return }
        resumeGame(id)
    }

    func resumeIfSeated() {
        guard let id = user?.inGameId else { return }
        resumeGame(id)
    }

    func resumeGame(_ id: String, spectate: Bool = false) {
        if let session = game, session.gameId == id, session.spectate == spectate {
            path = [.game(id, spectate: spectate)]
            if !session.connected, !session.finished {
                Task { await session.start() }
            }
            return
        }
        if let prev = game, prev.gameId != id {
            prev.stop()
        } else {
            game?.disconnectWithoutLeaving()
        }
        let session = GameSession(gameId: id, spectate: spectate)
        game = session
        path = [.game(id, spectate: spectate)]
        Task { await session.start() }
    }

    func detachFromGame() {
        hideAppTabs = false
        game?.disconnectWithoutLeaving()
        game = nil
        path.removeAll()
        Task {
            if let info = try? await APIClient.shared.userInfo() {
                user = info
            }
            await refreshLobby()
        }
    }

    func leaveActiveGame() {
        hideAppTabs = false
        game?.leave()
        game = nil
        path.removeAll()
        if var info = user {
            info.inGame = nil
            user = info
        }
        Task {
            if let info = try? await APIClient.shared.userInfo() {
                user = info
            }
            await refreshLobby()
        }
    }

    func startPresence() {
        guard isSignedIn else { return }
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isSignedIn else { break }
                await APIClient.shared.pingOnline()
                if let users = try? await APIClient.shared.onlineUsers() {
                    self.onlineUsers = users
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopPresence() {
        presenceTask?.cancel()
        presenceTask = nil
    }

    func openProfile(id: String, name: String) {
        path.append(.profile(id: id, name: name))
    }

    private func run(_ work: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await work() }
        catch { errorMessage = error.localizedDescription }
    }
}
