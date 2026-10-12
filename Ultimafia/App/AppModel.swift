import Foundation
import Observation

@Observable
final class AppModel {
    var user: UserInfo?
    var isRestoring = true
    var isBusy = false
    var errorMessage: String?
    /// The lobby list shows every lobby; the web API treats "All" as no lobby filter.
    let lobby = "All"
    var openGames: [GameSummary] = []
    var inProgressGames: [GameSummary] = []
    var finishedGames: [GameSummary] = []
    var finishedHasMore = true
    /// Finished-game replay. Kept apart from `game` so it never counts as seated.
    var reviewSession: GameSession?
    /// Pings received while seated but away from the game screen; shown on the Game tab.
    var mentionCount = 0
    /// Live game screen actually on screen (set by GameView appear/disappear, covers tab switches).
    var isViewingGame = false
    @ObservationIgnored private var finishedCursor: Double?
    @ObservationIgnored private var loadingFinished = false
    var path: [Route] = []
    var game: GameSession?
    var hideAppTabs = false
    /// Full-screen flows (setup search) that hide the app bar regardless of the game collapse state.
    var suppressAppBar = false
    /// The signed-in user's own custom emotes/stickers (`:name:` -> media path), loaded once per session.
    var myCustomEmotes: [String: String] = [:]
    var myCustomStickers: [String: String] = [:]
    /// Set when returning to the seated game from the lobby (vs. a fresh join/review).
    var resumingFromLobby = false
    var showLeaveConfirm = false
    var onlineUsers: [OnlineUser] = []
    @ObservationIgnored private var presenceTask: Task<Void, Never>?
    /// Email to prefill on the sign-in screen (saved account whose session expired).
    var loginPrefillEmail: String?

    enum Route: Hashable {
        case game(String, spectate: Bool)
        case profile(id: String, name: String)
        case family(id: String, name: String)
        case setupSearch
        case review(String)
    }

    /// True while the in-game screen is on top of the Play stack.
    var isOnGameScreen: Bool {
        if case .game = path.last { return true }
        return false
    }

    /// Game or review screen on top: the screens where the app bar can be collapsed with Hide.
    var isOnCollapsibleGameScreen: Bool {
        switch path.last {
        case .game, .review: return true
        default: return false
        }
    }

    /// True while a user profile is on top of the Play stack.
    var isOnProfile: Bool {
        switch path.last {
        case .profile, .family: return true
        default: return false
        }
    }

    /// Replace the Play stack. Swapping a pushed screen for a different destination in a single
    /// path write makes NavigationStack pop and push at once, which leaves a blank page; so pop
    /// to the lobby first and push the new route on the next run loop.
    func setPlayPath(_ newPath: [Route]) {
        guard !path.isEmpty, path.first != newPath.first else { path = newPath; return }
        path.removeAll()
        guard !newPath.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.path.isEmpty else { return }
            self.path = newPath
        }
    }

    /// Lobby button: pop the Play stack to the lobby root.
    func goToLobby() {
        hideAppTabs = false
        path.removeAll()
    }

    /// Leaving the Play tab from a profile drops the profile pages so they don't linger.
    func dropProfiles() {
        while let last = path.last {
            switch last {
            case .profile, .family: path.removeLast()
            default: return
            }
        }
    }

    var mentionBadge: Int {
        (seatedGameId != nil && game != nil && !isViewingGame) ? mentionCount : 0
    }

    /// Create button: open setup search (no-op if already there).
    func openCreate() {
        if path.last != .setupSearch { setPlayPath([.setupSearch]) }
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
        _ = DeviceIdentity.installId
        do {
            let info = try await APIClient.shared.userInfo()
            if info.id != nil {
                await didSignIn(info, email: nil)
            }
        } catch {
            user = nil
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            try await self.authenticate(email: email, password: password)
        }
    }

    /// Firebase idToken -> POST /auth (sets cookie) -> GET /user/info (csrf).
    private func authenticate(email: String, password: String) async throws {
        AccountStore.clearCookies()
        let token = try await FirebaseAuth.signIn(email: email, password: password)
        try await APIClient.shared.establishSession(idToken: token)
        let info = try await APIClient.shared.userInfo()
        guard let id = info.id else { throw UMError.message("Check your email to verify the account, then sign in.") }
        AccountStore.shared.savePassword(password, for: id)
        RememberedLogin.clear()
        await didSignIn(info, email: email)
    }

    /// Shared tail of every successful sign-in / restore / account switch.
    private func didSignIn(_ info: UserInfo, email: String?) async {
        guard let id = info.id else { return }
        user = info
        loginPrefillEmail = nil
        AccountStore.shared.upsert(info, email: email)
        AccountStore.shared.saveSession(for: id)
        DeviceIdentity.recordSignIn(userId: id)
        startPresence()
        Task { await self.loadMyCustomMedia() }
        await refreshLobby()
        resumeIfSeated()
    }

    /// Drop everything tied to the active account's session (keeps on-disk asset caches).
    /// Clears only per-account in-memory state. Device-wide caches (UMCustomAssetCache,
    /// UMImageCache, name fonts, role icons, sounds) are intentionally left alone.
    private func resetSessionState() {
        stopPresence()
        game?.disconnectWithoutLeaving()
        game = nil
        reviewSession?.stop()
        reviewSession = nil
        APIClient.shared.csrf = nil
        user = nil
        path = []
        hideAppTabs = false
        suppressAppBar = false
        isViewingGame = false
        resumingFromLobby = false
        showLeaveConfirm = false
        mentionCount = 0
        myCustomEmotes = [:]
        myCustomStickers = [:]
        onlineUsers = []
        openGames = []
        inProgressGames = []
        finishedGames = []
        finishedCursor = nil
        finishedHasMore = true
        errorMessage = nil
    }

    /// You tab: keep this account's session saved, go offline, and show sign-in for another account.
    /// The site has no explicit offline call; stopping the /user/online heartbeat lets it time out.
    func addAnotherAccount() {
        guard seatedGameId == nil else { return }
        if let id = user?.id { AccountStore.shared.saveSession(for: id) }
        resetSessionState()
        AccountStore.clearCookies()
    }

    /// Sign-in switcher: restore the saved cookie, verify with /user/info; else re-auth with the
    /// Keychain password; else prefill the email and ask for the password.
    /// A definite rejection (401/403, Firebase bad credentials, /user/info not logged in) of what
    /// was saved, including a session synced from another device, drops the saved account and its
    /// Keychain items. Network errors keep everything and ask to retry.
    func switchToAccount(_ account: SavedAccount) async {
        if let current = user?.id {
            if current == account.id { return }
            AccountStore.shared.saveSession(for: current)
        }
        resetSessionState()
        await run {
            var hadSaved = false
            var rejected = false
            if AccountStore.shared.restoreSession(for: account.id) {
                hadSaved = true
                do {
                    let info = try await APIClient.shared.userInfo()
                    if info.id == account.id {
                        await self.didSignIn(info, email: nil)
                        return
                    }
                    rejected = true // not logged in, or the cookie belongs to someone else
                } catch is UMAuthRejected {
                    rejected = true
                } catch {
                    AccountStore.clearCookies()
                    throw Self.retryError(error)
                }
                AccountStore.shared.clearSession(account.id)
                AccountStore.clearCookies()
            }
            if let email = account.email, let password = AccountStore.shared.password(for: account.id) {
                hadSaved = true
                do {
                    try await self.authenticate(email: email, password: password)
                    return
                } catch is UMAuthRejected {
                    rejected = true
                } catch {
                    // Couldn't check the password (offline, server error): keep everything.
                    AccountStore.clearCookies()
                    throw Self.retryError(error)
                }
            }
            self.loginPrefillEmail = account.email ?? ""
            if hadSaved && rejected {
                AccountStore.shared.remove(account.id)
                throw UMError.message("Your saved sign-in for \(account.name) expired. Please sign in again.")
            }
            throw UMError.message("Enter the password for \(account.name) to sign back in.")
        }
    }

    /// Network failures get a retry hint; other non-auth errors pass through unchanged.
    private static func retryError(_ error: Error) -> Error {
        guard error is URLError else { return error }
        return UMError.message("Couldn't reach Ultimafia (\(error.localizedDescription)). Check your connection and tap the account to try again.")
    }

    func removeSavedAccount(_ id: String) {
        AccountStore.shared.remove(id)
    }

    /// GET user/settings/data returns `customEmotes` / `customStickers` keyed by `:name:`.
    func loadMyCustomMedia() async {
        guard let data = try? await APIClient.shared.request("GET", path: "user/settings/data", query: [:], body: nil),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        func map(_ any: Any?) -> [String: String] {
            guard let dict = any as? [String: Any] else { return [:] }
            var out: [String: String] = [:]
            for (key, value) in dict {
                if let path = (value as? [String: Any])?["path"] as? String { out[key.lowercased()] = path }
            }
            return out
        }
        myCustomEmotes = map(obj["customEmotes"])
        myCustomStickers = map(obj["customStickers"])
    }

    func signUp(email: String, password: String) async {
        await run {
            _ = try await FirebaseAuth.signUp(email: email, password: password)
            self.errorMessage = "Account created. Verify the email we sent, then sign in."
        }
    }

    /// Signs out only the active account: its session and stored password are removed, but its
    /// row stays in the switcher (tapping it asks for the password). Other accounts are untouched.
    func signOut() async {
        let id = user?.id
        let email = id.flatMap { uid in AccountStore.shared.accounts.first { $0.id == uid }?.email }
        if seatedGameId != nil { game?.leave() }
        stopPresence()
        await APIClient.shared.logout()
        if let id {
            AccountStore.shared.clearSession(id)
            AccountStore.shared.clearPassword(id)
        }
        resetSessionState()
        loginPrefillEmail = email
    }

    func refreshLobby() async {
        do {
            async let open = APIClient.shared.gameList(list: "open", lobby: lobby)
            async let progress = APIClient.shared.gameList(list: "in progress", lobby: lobby)
            async let online = APIClient.shared.onlineUsers()
            let me = user?.id
            openGames = (try await open).filter { $0.isOpen && $0.isReviewVisible(to: me) }
            inProgressGames = (try await progress).filter { $0.isReviewVisible(to: me) }
            onlineUsers = (try? await online) ?? onlineUsers
            await loadFinished(reset: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadFinished(reset: Bool) async {
        guard !loadingFinished else { return }
        loadingFinished = true
        defer { loadingFinished = false }
        do {
            // A page can be all non-reviewable types; keep paging (bounded) so the
            // spinner row doesn't sit visible with nothing new to trigger it again.
            var attempts = 0
            repeat {
                attempts += 1
                let rows = try await APIClient.shared.finishedGames(before: reset ? nil : finishedCursor)
                // Cursor from the raw page so filtered-out game types don't stall paging.
                if let oldest = rows.compactMap(\.endTime).min() { finishedCursor = oldest }
                let kept = rows.filter { UMGameTypes.reviewable.contains($0.type ?? "") && $0.isReviewVisible(to: user?.id) }
                if reset && attempts == 1 {
                    finishedGames = kept
                } else {
                    let known = Set(finishedGames.map(\.id))
                    finishedGames += kept.filter { !known.contains($0.id) }
                }
                finishedHasMore = !rows.isEmpty
                if !kept.isEmpty { break }
            } while finishedHasMore && attempts < 4 && !reset
        } catch {
            if reset { finishedGames = [] }
            finishedHasMore = false
        }
    }

    func openReview(_ id: String) {
        let session = GameSession(gameId: id, spectate: true, review: true)
        reviewSession = session
        session.onReviewUnavailable = { [weak self] in self?.hideUnreviewable(id) }
        path.append(.review(id))
        Task { await session.start() }
    }

    /// Safety net for the list-side filter: drop a game whose review the server refused.
    func hideUnreviewable(_ id: String) {
        finishedGames.removeAll { $0.id == id }
        inProgressGames.removeAll { $0.id == id }
        openGames.removeAll { $0.id == id }
    }

    func closeReview() {
        reviewSession = nil
        if case .review = path.last { path.removeLast() }
    }

    func openGame(_ summary: GameSummary, spectate: Bool = false) {
        resumeGame(summary.id, spectate: spectate)
    }

    func resumeSeatedGame() {
        guard let id = seatedGameId else { return }
        resumingFromLobby = true
        resumeGame(id)
    }

    func resumeIfSeated() {
        guard let id = user?.inGameId else { return }
        resumeGame(id)
    }

    func resumeGame(_ id: String, spectate: Bool = false) {
        if let session = game, session.gameId == id, session.spectate == spectate {
            setPlayPath([.game(id, spectate: spectate)])
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
        session.onMention = { [weak self] in
            guard let self, !self.isViewingGame else { return }
            self.mentionCount += 1
        }
        mentionCount = 0
        game = session
        setPlayPath([.game(id, spectate: spectate)])
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

    func openFamily(id: String, name: String) {
        path.append(.family(id: id, name: name))
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
