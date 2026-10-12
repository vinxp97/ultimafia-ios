import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct GameView: View {
    @Environment(AppModel.self) private var app
    var review = false
    @State private var draft = ""
    @State private var selectedPanel = 0
    @FocusState private var chatFocused: Bool

    var body: some View {
        Group {
            if review, let session = app.reviewSession {
                GameScreen(
                    session: session,
                    draft: $draft,
                    selectedPanel: $selectedPanel,
                    chatFocused: $chatFocused,
                    onLeave: { app.closeReview() },
                    onDetach: { app.closeReview() }
                )
            } else if !review, let session = app.game {
                GameScreen(
                    session: session,
                    draft: $draft,
                    selectedPanel: $selectedPanel,
                    chatFocused: $chatFocused,
                    onLeave: { app.leaveActiveGame() },
                    onDetach: { app.detachFromGame() }
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(UMTheme.bg.ignoresSafeArea())
            }
        }
    }
}

private struct GameScreen: View {
    @Environment(AppModel.self) private var app
    @State private var didAppearOnce = false
    var session: GameSession
    @Binding var draft: String
    @Binding var selectedPanel: Int
    var chatFocused: FocusState<Bool>.Binding
    var onLeave: () -> Void
    var onDetach: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GameHeader(session: session, onClose: session.isReview ? onLeave : nil)
            SetupRoleStrip(session: session)
            Divider().overlay(UMTheme.line)
            Group {
                switch selectedPanel {
                case 1:
                    GameTownPane(session: session)
                case 2:
                    GameActPane(session: session)
                default:
                    GameChatPane(
                        session: session,
                        draft: $draft,
                        chatFocused: chatFocused
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            GamePanelPicker(session: session, selectedPanel: $selectedPanel)
        }
        .background(UMTheme.bg.ignoresSafeArea())
        .toolbar(app.hideAppTabs || session.isReview ? .hidden : .automatic, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .alert("Game", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
        .onChange(of: session.displaced) { _, displaced in
            if displaced { onDetach() }
        }
        .task { await RoleCatalog.shared.load() }
        // Entering a game or review collapses the bottom bar, like tapping Hide; restore it on the way out.
        .onAppear {
            // Collapse the bar on a fresh join/review, or when coming back from the lobby with a ping badge.
            // Switching back from the You tab leaves it as it was.
            if !didAppearOnce {
                didAppearOnce = true
                let fromLobby = app.resumingFromLobby
                app.resumingFromLobby = false
                if !fromLobby || app.mentionBadge > 0 { app.hideAppTabs = true }
            }
            if !session.isReview {
                app.isViewingGame = true
                app.mentionCount = 0
            }
        }
        .onDisappear { if !session.isReview { app.isViewingGame = false } }
        // Left the game screen for the lobby (not just another tab): bring the bar back.
        .onDisappear { if !app.isOnGameScreen { app.hideAppTabs = false } }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil; onDetach() } }
        )
    }
}

private struct GameHeader: View {
    var session: GameSession
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to games")
                Text("REVIEW")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(UMTheme.blood.opacity(0.25), in: Capsule())
                    .foregroundStyle(UMTheme.blood)
            } else {
                Circle()
                    .fill(session.connected ? UMTheme.village : UMTheme.mafia)
                    .frame(width: 8, height: 8)
            }
            Text(session.setupName ?? session.gameType ?? "Game")
                .font(.headline)
                .lineLimit(1)
            if session.finished, !session.isReview {
                Text("Finished")
                    .font(.caption)
                    .foregroundStyle(UMTheme.muted)
            }
            if session.readyCheckActive {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let left = max(0, Int(session.readyEndTime.timeIntervalSince(context.date).rounded(.up)))
                    Text("Ready \(left)s")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(left < 10 ? UMTheme.mafia : UMTheme.village)
                }
            }
            Spacer(minLength: 8)
            PhaseTimerBadge(session: session)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(UMTheme.card)
    }
}

private struct GamePanelPicker: View {
    var session: GameSession
    @Binding var selectedPanel: Int
    @Environment(AppModel.self) private var app
    @State private var showGuides = false
    @AppStorage("um.showSetupGuides") private var showSetupGuides = true

    var body: some View {
        HStack(spacing: 4) {
            tabBtn("Village", 1, "person.3")
            tabBtn("Chat", 0, "text.bubble")
            tabBtn("Act", 2, "hand.raised")
            if showSetupGuides, session.setupId != nil { guidesBtn }
            hideBtn
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(UMTheme.card)
        .sheet(isPresented: $showGuides) {
            if let id = session.setupId {
                GuidesView(setupId: id, setupName: session.setupName, gameType: session.setupGameType,
                           otherRoles: session.guessableRoles.map(\.raw))
            }
        }
    }

    private var guidesBtn: some View {
        Button { showGuides = true } label: {
            Label("Guides", systemImage: "book")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(UMTheme.muted)
        .accessibilityLabel("Setup guides")
    }

    private var hideBtn: some View {
        Button {
            app.hideAppTabs.toggle()
        } label: {
            Label("Hide", systemImage: app.hideAppTabs ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(app.hideAppTabs ? UMTheme.elevated : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(app.hideAppTabs ? .white : UMTheme.muted)
        .accessibilityLabel(app.hideAppTabs ? "Show Play and You" : "Hide Play and You")
    }

    private func tabBtn(_ title: String, _ tag: Int, _ icon: String) -> some View {
        Button {
            selectedPanel = tag
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selectedPanel == tag ? UMTheme.elevated : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedPanel == tag ? .white : UMTheme.muted)
    }
}

/// Non-observed buffer so scroll-visibility callbacks coalesce into one state update per frame.
private final class VisibleIdBuffer {
    var pending: Set<String> = []
    var scheduled = false
}

private struct ChatScrollPin: Equatable {
    var atBottom: Bool
    var atTop: Bool
    var contentH: CGFloat
    var containerH: CGFloat
}

private struct GameChatPane: View {
    var session: GameSession
    @Binding var draft: String
    var chatFocused: FocusState<Bool>.Binding
    @AppStorage("um.chatLayout") private var chatLayout: ChatLayout = .standard
    @AppStorage("um.showTypingIndicator") private var showTypingIndicator = true
    @AppStorage("um.showVotingLog") private var showVotingLog = true
    @State private var stickToBottom = true
    @State private var unreadCount = 0
    @State private var atTop = false
    @State private var visibleLineIds: Set<String> = []
    @State private var visibleBuffer = VisibleIdBuffer()

    private var chatLines: [ChatLine] {
        session.displayedMessages.filter { showVotingLog || !$0.isVoteLog }
    }

    /// Every line that has ever been on screen (or was already there when the chat opened).
    private var seenLineIds: Set<String> {
        get { session.chatSeenLineIds }
        nonmutating set { session.chatSeenLineIds = newValue }
    }

    private func markAllSeen() {
        seenLineIds.formUnion(chatLines.map(\.id))
    }

    /// Unseen = live messages that have never been on screen. Reviews have no incoming messages.
    private func recomputeUnread() {
        guard !session.isReview, session.isViewingLive else { unreadCount = 0; return }
        seenLineIds.formUnion(visibleLineIds)
        if stickToBottom { markAllSeen(); unreadCount = 0; return }
        unreadCount = chatLines.reduce(0) { $0 + (seenLineIds.contains($1.id) ? 0 : 1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PhaseBar(session: session)
            ScrollViewReader { proxy in
                ScrollView {
                    let lines = chatLines
                    LazyVStack(alignment: .leading, spacing: chatLayout == .compact ? 4 : 2) {
                        Color.clear
                            .frame(height: 1)
                            .id("chat-top")
                        ForEach(session.viewingNewspapers) { paper in
                            NewspaperCard(issue: paper, session: session)
                                .id("newspaper-\(paper.id)")
                        }
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            ChatRow(
                                line: line,
                                previous: index > 0 ? lines[index - 1] : nil,
                                session: session,
                                layout: chatLayout
                            )
                            .id(line.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("chat-bottom")
                    }
                    .scrollTargetLayout()
                    .padding(12)
                    .padding(.bottom, 16)
                }
                .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.6) { ids in
                    let buffer = visibleBuffer
                    buffer.pending = Set(ids)
                    guard !buffer.scheduled else { return }
                    buffer.scheduled = true
                    DispatchQueue.main.async {
                        buffer.scheduled = false
                        guard buffer.pending != visibleLineIds else { return }
                        visibleLineIds = buffer.pending
                        session.chatAnchorId = chatLines.first(where: { buffer.pending.contains($0.id) })?.id
                        recomputeUnread()
                    }
                }
                .pointerScrolling()
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .overlay(alignment: .top) {
                    if !atTop {
                        Button {
                            jumpToTop(proxy: proxy)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.body.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(UMTheme.card.opacity(0.92), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        .accessibilityLabel("Scroll to top")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if showTypingIndicator, stickToBottom {
                        VStack(alignment: .trailing, spacing: 6) {
                            ForEach(session.typingPlayers) { player in
                                HStack(spacing: 4) {
                                    UMAvatarView(player: player, size: 22)
                                    PulsingDots()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(UMTheme.card.opacity(0.92), in: Capsule())
                            }
                        }
                        .padding(.trailing, 6)
                        .padding(.top, 4)
                    }
                }
                .onScrollGeometryChange(for: ChatScrollPin.self) { geo in
                    ChatScrollPin(atBottom: pinnedToLatest(geo), atTop: pinnedToTop(geo), contentH: geo.contentSize.height.rounded(), containerH: geo.containerSize.height.rounded())
                } action: { old, pin in
                    if atTop != pin.atTop { atTop = pin.atTop }
                    // Keyboard open/close or new content resizes things; stay pinned and follow.
                    if stickToBottom, abs(pin.containerH - old.containerH) > 1 {
                        // Defer the scroll so it doesn't re-trigger geometry updates within this frame.
                        DispatchQueue.main.async {
                            if stickToBottom { jumpToLatest(proxy: proxy) }
                        }
                        return
                    }
                    if stickToBottom, pin.contentH > old.contentH + 1 {
                        return
                    }
                    if stickToBottom != pin.atBottom {
                        stickToBottom = pin.atBottom
                        recomputeUnread()
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if !stickToBottom, !session.isReview {
                            Button {
                                markAllSeen()
                                unreadCount = 0
                                stickToBottom = true
                                jumpToLatest(proxy: proxy)
                            } label: {
                                Text(unreadCount > 0 ? "\(unreadCount) unseen message\(unreadCount == 1 ? "" : "s") ↓" : "Scroll to latest message ↓")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(UMTheme.blood, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 8)
                            .accessibilityLabel(unreadCount > 0 ? "\(unreadCount) unseen messages, scroll to latest" : "Scroll to latest message")
                        }
                        VStack(spacing: 0) {
                            if session.showComposer {
                                ChatComposer(
                                    session: session,
                                    draft: $draft,
                                    chatFocused: chatFocused
                                )
                            }
                        }
                        .background(UMTheme.elevated)
                    }
                }
                .onChange(of: session.displayedMessages.count) { old, new in
                    if stickToBottom {
                        markAllSeen()
                        unreadCount = 0
                        jumpToLatestIfPinned(proxy: proxy)
                    } else {
                        recomputeUnread()
                    }
                }
                .onChange(of: session.viewingPhaseId) { _, _ in
                    markAllSeen()
                    unreadCount = 0
                    stickToBottom = true
                    jumpToLatest(proxy: proxy)
                }
                .onChange(of: chatFocused.wrappedValue) { _, focused in
                    guard focused, stickToBottom else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if stickToBottom { jumpToLatest(proxy: proxy) }
                    }
                }
                .onAppear {
                    // Returning from the lobby: restore position and keep unseen messages unseen.
                    if session.chatHasOpened, !session.chatPinnedToBottom, let anchor = session.chatAnchorId,
                       chatLines.contains(where: { $0.id == anchor }) {
                        stickToBottom = false
                        DispatchQueue.main.async { proxy.scrollTo(anchor, anchor: .top) }
                        recomputeUnread()
                    } else {
                        markAllSeen()
                        stickToBottom = true
                        jumpToLatest(proxy: proxy)
                    }
                    session.chatHasOpened = true
                }
                .onChange(of: stickToBottom) { _, pinned in
                    session.chatPinnedToBottom = pinned
                }
            }
        }
    }

    private func pinnedToLatest(_ geo: ScrollGeometry) -> Bool {
        let slack: CGFloat = 48
        if geo.contentSize.height <= geo.containerSize.height + slack {
            return true
        }
        return geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - slack
    }

    private func pinnedToTop(_ geo: ScrollGeometry) -> Bool {
        geo.contentOffset.y <= 24
    }

    private func jumpToLatestIfPinned(proxy: ScrollViewProxy) {
        guard session.isViewingLive, let last = session.displayedMessages.last else { return }
        let mine = last.senderId == session.selfId
        if stickToBottom || mine {
            stickToBottom = true
            jumpToLatest(proxy: proxy)
        }
    }

    private func jumpToLatest(proxy: ScrollViewProxy) {
        let target = session.displayedMessages.last?.id ?? "chat-bottom"
        proxy.scrollTo(target, anchor: .bottom)
    }

    private func jumpToTop(proxy: ScrollViewProxy) {
        stickToBottom = false
        proxy.scrollTo("chat-top", anchor: .top)
    }
}

private struct ChatComposer: View {
    var session: GameSession
    @Binding var draft: String
    var chatFocused: FocusState<Bool>.Binding
    @State private var savedDraft = ""
    @AppStorage("um.showNameAutofill") private var showTabButton = true
    @AppStorage("um.showEmoteAutocomplete") private var showEmoteAutocomplete = true
    @Environment(AppModel.self) private var app
    @State private var keyboardExpanded = false

    private struct MediaSuggestion: Identifiable {
        var id: String { (isSticker ? "s" : "e") + code }
        let code: String
        let url: URL
        let isSticker: Bool
    }

    /// Current word when it looks like `:x...` (colon then at least one letter).
    private var colonToken: (query: String, range: Range<String.Index>)? {
        guard let last = draft.last, !last.isWhitespace, !draft.hasPrefix("/") else { return nil }
        let start = draft.lastIndex(where: { $0.isWhitespace }).map { draft.index(after: $0) } ?? draft.startIndex
        let word = draft[start...]
        guard word.hasPrefix(":"), word.count >= 2, word.dropFirst().first?.isLetter == true else { return nil }
        var q = String(word.dropFirst()).lowercased()
        if q.hasSuffix(":") { q.removeLast() }
        return (q, start..<draft.endIndex)
    }

    /// Own custom emotes and stickers only. API data first, in-game self player maps as fallback.
    private var mediaSuggestions: [MediaSuggestion] {
        guard showEmoteAutocomplete, chatFocused.wrappedValue, let t = colonToken else { return [] }
        let me = app.user?.id
        let selfPlayer = me.flatMap { id in session.players.first { $0.userId == id || $0.id == id } }
        let emotes = app.myCustomEmotes.isEmpty ? (selfPlayer?.customEmotes ?? [:]) : app.myCustomEmotes
        let stickers = app.myCustomStickers.isEmpty ? (selfPlayer?.customStickers ?? [:]) : app.myCustomStickers
        func ranked(_ map: [String: String], sticker: Bool) -> [MediaSuggestion] {
            let items = map.compactMap { code, path -> (String, URL)? in
                guard let url = UMMediaURL.resolve(path) else { return nil }
                let bare = code.trimmingCharacters(in: CharacterSet(charactersIn: ":")).lowercased()
                return bare.contains(t.query) ? (code, url) : nil
            }
            let bare: (String) -> String = { $0.trimmingCharacters(in: CharacterSet(charactersIn: ":")).lowercased() }
            return items.sorted { a, b in
                let pa = bare(a.0).hasPrefix(t.query), pb = bare(b.0).hasPrefix(t.query)
                return pa != pb ? pa : a.0 < b.0
            }.map { MediaSuggestion(code: $0.0, url: $0.1, isSticker: sticker) }
        }
        return ranked(emotes, sticker: false) + ranked(stickers, sticker: true)
    }

    private func applyMedia(_ item: MediaSuggestion) {
        guard let t = colonToken else { return }
        var next = draft
        next.replaceSubrange(t.range, with: item.code + " ")
        draft = String(next.prefix(UMConfig.maxChatLength))
        session.noteTyping()
    }

    /// Last word of the draft (cursor is assumed at the end), keeping any leading @ or %.
    private var nameToken: (prefix: String, query: String, range: Range<String.Index>)? {
        guard let last = draft.last, !last.isWhitespace else { return nil }
        let start = draft.lastIndex(where: { $0.isWhitespace }).map { draft.index(after: $0) } ?? draft.startIndex
        let word = draft[start...]
        let prefix = String(word.prefix(while: { $0 == "@" || $0 == "%" }))
        let query = String(word.dropFirst(prefix.count))
        guard query.count >= 2, !draft.hasPrefix("/") else { return nil }
        return (prefix, query, start..<draft.endIndex)
    }

    private var nameSuggestions: [String] {
        guard showTabButton, chatFocused.wrappedValue, colonToken == nil, let t = nameToken else { return [] }
        var seen = Set<String>()
        return session.players.map(\.name).filter { name in
            name.lowercased().hasPrefix(t.query.lowercased())
                && name.caseInsensitiveCompare(t.query) != .orderedSame
                && seen.insert(name).inserted
        }.prefix(3).map { $0 }
    }

    private func applySuggestion(_ name: String) {
        guard let t = nameToken else { return }
        var next = draft
        next.replaceSubrange(t.range, with: t.prefix + name + " ")
        draft = String(next.prefix(UMConfig.maxChatLength))
        session.noteTyping()
    }

    var body: some View {
        VStack(spacing: 0) {
        let media = session.isSpeakCoolingDown ? [] : mediaSuggestions
        if !media.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(media) { item in
                        Button { applyMedia(item) } label: {
                            HStack(spacing: 5) {
                                AnimatedWebPView(url: item.url, showsPlaceholder: false, fitHeight: 20)
                                    .fixedSize()
                                Text(item.code)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                if item.isSticker {
                                    Text("STICKER")
                                        .font(.system(size: 9, weight: .heavy))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(UMTheme.blood.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            .frame(height: 20)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(UMTheme.card, in: Capsule())
                            .overlay(Capsule().stroke(item.isSticker ? UMTheme.blood.opacity(0.7) : UMTheme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .accessibilityLabel(item.isSticker ? "Sticker \(item.code)" : "Emote \(item.code)")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(UMTheme.elevated)
        } else if !session.isSpeakCoolingDown, !nameSuggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(nameSuggestions, id: \.self) { name in
                        Button { applySuggestion(name) } label: {
                            Text(name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(UMTheme.card, in: Capsule())
                                .overlay(Capsule().stroke(UMTheme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(UMTheme.elevated)
        }
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let cooling = (session.speakCooldownUntil ?? .distantPast) > context.date
            HStack(alignment: .center, spacing: 8) {
                Button {
                    session.cycleSpeechOption()
                } label: {
                    Text(session.speechLabel)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(minWidth: 52)
                        .background(UMTheme.card, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(cooling)
                .contextMenu {
                    ForEach(session.speechOptions) { option in
                        Button(option.menuTitle) {
                            session.selectSpeechOption(option.id)
                        }
                    }
                }

                TextField(placeholder(cooling: cooling), text: cappedDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(fieldBackground(cooling: cooling), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(cooling ? Color.white : Color.primary)
                    .focused(chatFocused)
                    .disabled(cooling)
                    .onSubmit(send)
                    .onChange(of: draft) { oldValue, newValue in
                        if cooling { return }
                        handleTyping(oldValue, newValue)
                    }
                    .onKeyPress(.tab) {
                        if cooling { return KeyPress.Result.ignored }
                        return completeName() ? KeyPress.Result.handled : KeyPress.Result.ignored
                    }

                Button("Send", action: send)
                    .disabled(cooling || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .tint(UMTheme.blood)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(UMTheme.elevated)
            .onChange(of: cooling) { _, nowCooling in
                if nowCooling {
                    if !draft.isEmpty {
                        savedDraft = draft
                        draft = ""
                    }
                    session.stopTyping()
                } else if draft.isEmpty, !savedDraft.isEmpty {
                    draft = savedDraft
                    savedDraft = ""
                }
            }
        }
        }
        .bindKeyboardExpanded($keyboardExpanded)
    }

    private func placeholder(cooling: Bool) -> String {
        if cooling {
            let left = session.speakCooldownSecondsLeft
            return "Please do not spam! \(max(left, 1))s"
        }
        return session.speechPlaceholder
    }

    private func fieldBackground(cooling: Bool) -> Color {
        cooling ? Color.red.opacity(0.72) : UMTheme.card
    }

    private var cappedDraft: Binding<String> {
        Binding(
            get: { draft },
            set: { draft = String($0.prefix(UMConfig.maxChatLength)) }
        )
    }

    @discardableResult
    private func completeName() -> Bool {
        guard let next = session.completePlayerName(draft), next != draft else { return false }
        draft = String(next.prefix(UMConfig.maxChatLength))
        if !draft.hasPrefix("/") { session.noteTyping() }
        return true
    }

    private func handleTyping(_ oldValue: String, _ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            session.stopTyping()
            return
        }
        if newValue.hasPrefix("/") {
            session.stopTyping()
            return
        }
        if newValue != oldValue {
            session.noteTyping()
        }
    }

    private func send() {
        guard !session.isSpeakCoolingDown else { return }
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.stopTyping()
        if session.speak(text) {
            draft = ""
        }
        chatFocused.wrappedValue = true
    }
}

private struct ChatRow: View {
    let line: ChatLine
    var previous: ChatLine?
    var session: GameSession
    var layout: ChatLayout = .standard

    private var grouped: Bool {
        guard layout == .standard else { return false }
        if line.isQuote { return false }
        guard isPlayerChat(line), let previous, isPlayerChat(previous), !previous.isQuote else { return false }
        return previous.senderId == line.senderId
    }

    private func isPlayerChat(_ line: ChatLine) -> Bool {
        !line.isServer && line.senderId != "vote" && line.senderId != "server"
    }

    var body: some View {
        let player = session.player(for: line.senderId)
        Group {
            if let paper = line.newspaper {
                NewspaperCard(issue: paper, session: session)
            } else if line.senderId == "vote" {
                voteRow
            } else if line.isServer {
                serverRow
            } else if layout == .compact {
                compactRow(player: player)
            } else {
                standardRow(player: player)
            }
        }
        .frame(maxWidth: .infinity, alignment: line.senderId == "vote" ? .trailing : .leading)
        .contentShape(Rectangle())
        .opacity(line.isQuote ? 0.9 : 1)
        .padding(.top, grouped ? 0 : (layout == .standard && isPlayerChat(line) ? 8 : 0))
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                session.quote(line)
            }
        )
    }

    private var voteRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(minuteSecond(line.time))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(UMTheme.muted)
                .frame(width: 36, alignment: .leading)
                .fixedSize()
                .padding(.top, 2)
            Spacer(minLength: 0)
            Text(line.content)
                .font(.caption.italic())
                .foregroundStyle(UMTheme.muted)
                .multilineTextAlignment(.trailing)
        }
    }

    private var serverRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(minuteSecond(line.time))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(UMTheme.muted)
                .frame(width: 36, alignment: .leading)
                .fixedSize()
                .padding(.top, 2)
            EmoteText(text: line.content, color: UMTheme.muted, italic: true, system: true, emoteSize: 16, players: session.players, gameType: session.setupGameType, otherRoles: session.guessableRoles.map(\.raw))
        }
    }

    private func compactRow(player: GamePlayer?) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(minuteSecond(line.time))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(UMTheme.muted)
                .frame(width: 36, alignment: .leading)
                .fixedSize()
                .padding(.top, 2)
            playerRow(player: player)
        }
    }

    private func standardRow(player: GamePlayer?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !grouped {
                HStack(alignment: .center, spacing: 6) {
                    UMAvatarView(
                        userId: player?.userId,
                        hasAvatar: player?.avatar ?? false,
                        name: player?.name ?? line.senderName,
                        size: 28,
                        square: player?.squareAvatar ?? false
                    )
                    Group {
                        if let player {
                            PlayerNameView(player: player, fontSize: 14, dead: line.senderWasDead)
                        } else {
                            Text(line.senderId == "anonymous" ? "Anonymous" : line.senderName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.white)
                        }
                    }
                    Text(minuteSecond(line.time))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(UMTheme.muted)
                    Spacer(minLength: 0)
                }
            }
            messageBody(player: player)
        }
    }

    @ViewBuilder
    private func messageBody(player: GamePlayer?) -> some View {
        let me = line.content.hasPrefix("/me ")
        let body = me ? String(line.content.dropFirst(4)) : line.content
        HStack(alignment: .top, spacing: 4) {
            if line.isQuote {
                Image(systemName: "quote.opening")
                    .font(.caption2)
                    .foregroundStyle(UMTheme.muted)
                    .padding(.top, 3)
            }
            if line.isQuote {
                quoteAuthorLabel
            }
            if let prefix = line.prefix, !prefix.isEmpty {
                Text(prefix)
                    .font(.caption2.italic())
                    .foregroundStyle(UMTheme.muted)
                    .fixedSize()
            }
            EmoteText(
                text: body,
                color: line.isQuote ? UMTheme.muted : chatBodyColor(player: player),
                italic: me || line.isQuote,
                customEmotes: line.isQuote ? line.customEmotes : (player?.customEmotes ?? line.customEmotes),
                customStickers: line.isQuote ? line.customStickers : (player?.customStickers ?? line.customStickers),
                system: false,
                players: session.players,
                gameType: session.setupGameType,
                otherRoles: session.guessableRoles.map(\.raw)
            )
            if line.isQuote {
                Image(systemName: "quote.closing")
                    .font(.caption2)
                    .foregroundStyle(UMTheme.muted)
                    .padding(.top, 3)
            }
        }
    }

    private var quotedAuthor: String {
        if let name = line.quotedSenderName, !name.isEmpty { return name }
        if line.quotedSenderId == "anonymous" { return "Anonymous" }
        return "Anonymous"
    }

    @ViewBuilder
    private var quoteAuthorLabel: some View {
        let name = quotedAuthor
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let quotedTime = line.quotedTime {
                Text(minuteSecond(quotedTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(UMTheme.muted)
                    .fixedSize()
            }
            if let phase = line.quotedFromStateName, !phase.isEmpty {
                Text("\(name) on \(phase):")
                    .font(.caption.italic())
                    .foregroundStyle(UMTheme.muted)
                    .fixedSize()
            } else {
                Text("\(name):")
                    .font(.caption.italic())
                    .foregroundStyle(UMTheme.muted)
                    .fixedSize()
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func playerRow(player: GamePlayer?) -> some View {
        let me = line.content.hasPrefix("/me ")
        let body = me ? String(line.content.dropFirst(4)) : line.content
        UMAvatarView(
            userId: player?.userId,
            hasAvatar: player?.avatar ?? false,
            name: player?.name ?? line.senderName,
            size: 18,
            square: player?.squareAvatar ?? false
        )
        .offset(y: -1.5)
        .padding(.top, 2)

        if line.isQuote {
            Image(systemName: "quote.opening")
                .font(.caption2)
                .foregroundStyle(UMTheme.muted)
                .padding(.top, 3)
        }

        Group {
            if line.isQuote {
                quoteAuthorLabel
            } else if let player {
                PlayerNameView(player: player, fontSize: 14, dead: line.senderWasDead)
            } else {
                Text(line.senderId == "anonymous" ? "Anonymous" : line.senderName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .fixedSize()
        if let prefix = line.prefix, !prefix.isEmpty {
            Text(prefix)
                .font(.caption2.italic())
                .foregroundStyle(UMTheme.muted)
                .fixedSize()
        }

        EmoteText(
            text: body,
            color: line.isQuote ? UMTheme.muted : chatBodyColor(player: player),
            italic: me || line.isQuote,
            customEmotes: line.isQuote ? line.customEmotes : (player?.customEmotes ?? line.customEmotes),
            customStickers: line.isQuote ? line.customStickers : (player?.customStickers ?? line.customStickers),
            system: false,
            players: session.players,
            gameType: session.setupGameType,
            otherRoles: session.guessableRoles.map(\.raw)
        )
        if line.isQuote {
            Image(systemName: "quote.closing")
                .font(.caption2)
                .foregroundStyle(UMTheme.muted)
                .padding(.top, 3)
        }
    }

    private func chatBodyColor(player: GamePlayer?) -> Color {
        if line.senderWasDead { return .red }
        return player?.bodyColor ?? .white
    }

    private func minuteSecond(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.minute, .second], from: date)
        return String(format: "%02d:%02d", c.minute ?? 0, c.second ?? 0)
    }
}

private struct GameTownPane: View {
    var session: GameSession
    @State private var pickingPlayerId: String?

    var body: some View {
        List {
            Section {
                ForEach(session.villagePlayers) { player in
                    townRow(player, dead: false)
                }
            }
            if !session.graveyardPlayers.isEmpty {
                Section("Graveyard") {
                    ForEach(session.graveyardPlayers) { player in
                        townRow(player, dead: true)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pointerScrolling()
        .confirmationDialog("Mark role as", isPresented: pickingBinding, titleVisibility: .visible) {
            ForEach(session.guessableRoles) { role in
                Button(role.modifiers.isEmpty ? role.name : "\(role.name) (\(role.modifiers.joined(separator: "/")))") {
                    if let id = pickingPlayerId {
                        session.pickRoleGuess(playerId: id, role: role.raw)
                    }
                    pickingPlayerId = nil
                }
            }
            Button("Cancel", role: .cancel) { pickingPlayerId = nil }
        }
    }

    private func townRow(_ player: GamePlayer, dead: Bool) -> some View {
        HStack(spacing: 10) {
            if session.isGameInProgress {
                RoleGuessBadge(session: session, player: player) {
                    pickingPlayerId = player.id
                }
            }
            UMAvatarView(player: player, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                PlayerNameView(player: player, fontSize: 16, dead: dead)
                if player.id == session.selfId {
                    HStack(spacing: 6) {
                        Text("you").font(.caption2).foregroundStyle(UMTheme.muted)
                        if let role = session.selfRoleName {
                            Text(role).font(.caption2.weight(.semibold)).foregroundStyle(UMTheme.blood)
                        }
                    }
                } else if session.teammateIds.contains(player.id) {
                    HStack(spacing: 6) {
                        Text("teammate").font(.caption2).foregroundStyle(UMTheme.mafia)
                        if let role = session.knownRoles[player.id] {
                            Text(role.split(separator: ":").first.map(String.init) ?? role)
                                .font(.caption2)
                                .foregroundStyle(UMTheme.muted)
                        }
                    }
                }
            }
            Spacer()
        }
        .listRowBackground(UMTheme.card)
    }

    private var pickingBinding: Binding<Bool> {
        Binding(
            get: { pickingPlayerId != nil },
            set: { if !$0 { pickingPlayerId = nil } }
        )
    }
}

private struct GameActPane: View {
    var session: GameSession

    private var actMeetings: [VoteMeeting] {
        session.meetingsForViewing.filter { !$0.isVoteKick }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if actMeetings.isEmpty {
                    Text(emptyCopy)
                        .foregroundStyle(UMTheme.muted)
                        .padding(16)
                }
                ForEach(actMeetings) { meeting in
                    MeetingBlock(session: session, meeting: meeting)
                }
            }
            .padding(16)
        }
        .pointerScrolling()
    }

    private var emptyCopy: String {
        if session.spectate { return "Spectating. No actions." }
        if !session.isViewingLive { return "No actions in this phase." }
        return "No actions right now."
    }
}

private struct ActVoteRow: Identifiable {
    var id: String
    var title: String
    var isVoter: Bool
    var canBeTarget: Bool
    var theirVote: String
    var votesOnThem: Int
}

private struct MeetingBlock: View {
    var session: GameSession
    var meeting: VoteMeeting
    @State private var textDraft = ""

    private var clickable: Bool {
        session.isViewingLive && meeting.canVote && !session.spectate
    }

    private var rows: [ActVoteRow] {
        var out: [ActVoteRow] = []
        var seen = Set<String>()
        for member in meeting.members {
            seen.insert(member.id)
            let sel = meeting.selections(of: member.id)
            let their = sel.map { session.voteLabel($0, meeting: meeting) }.joined(separator: ", ")
            out.append(ActVoteRow(
                id: member.id,
                title: session.displayVoter(member.id, meeting: meeting),
                isVoter: member.canVote,
                canBeTarget: meeting.targets.contains(member.id),
                theirVote: their,
                votesOnThem: meeting.count(for: member.id)
            ))
        }
        for target in meeting.targets where !seen.contains(target) {
            seen.insert(target)
            out.append(ActVoteRow(
                id: target,
                title: session.voteLabel(target, meeting: meeting),
                isVoter: false,
                canBeTarget: true,
                theirVote: "",
                votesOnThem: meeting.count(for: target)
            ))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(meeting.actionName)
                    .font(.headline)
                Spacer(minLength: 8)
                if let item = meeting.itemName, !item.isEmpty {
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(UMTheme.muted)
                }
            }
            if meeting.inputType == "text" {
                if clickable {
                    HStack(spacing: 8) {
                        TextField("Type…", text: $textDraft)
                            .textFieldStyle(.roundedBorder)
                        Button("Send") {
                            let s = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !s.isEmpty else { return }
                            session.vote(meetingId: meeting.id, selection: s)
                            textDraft = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(UMTheme.blood)
                    }
                }
            } else if meeting.inputType == "player" || meeting.inputType.isEmpty {
                ForEach(rows) { row in
                    playerRow(row)
                }
            } else {
                ForEach(meeting.targets, id: \.self) { target in
                    targetRow(target)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func playerRow(_ row: ActVoteRow) -> some View {
        let mine = meeting.selections(of: session.selfId).contains(row.id)
        let canTap = clickable && row.canBeTarget
        return Button {
            guard canTap else { return }
            session.vote(meetingId: meeting.id, selection: row.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if row.isVoter {
                    Text("votes")
                        .font(.subheadline)
                        .foregroundStyle(UMTheme.muted)
                    if !row.theirVote.isEmpty {
                        Text(row.theirVote)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(UMTheme.roleMention)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text("\(row.votesOnThem)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(mine ? UMTheme.village : UMTheme.muted)
            }
            .lineLimit(1)
            .padding(10)
            .background(mine ? UMTheme.blood.opacity(0.35) : UMTheme.elevated, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!canTap)
    }

    private func targetRow(_ target: String) -> some View {
        let mine = meeting.selections(of: session.selfId).contains(target)
        let count = meeting.count(for: target)
        return Button {
            guard clickable else { return }
            session.vote(meetingId: meeting.id, selection: target)
        } label: {
            HStack {
                Text(session.voteLabel(target, meeting: meeting))
                Spacer()
                if mine {
                    Text("YOUR VOTE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(UMTheme.village)
                }
                Text("\(count)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(UMTheme.muted)
            }
            .padding(10)
            .background(mine ? UMTheme.blood.opacity(0.35) : UMTheme.elevated, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!clickable)
    }
}


#if canImport(UIKit)
private struct KeyboardExpandedBinder: ViewModifier {
    @Binding var expanded: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                let height = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
                expanded = height > 160
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                expanded = false
            }
    }
}
#endif

private extension View {
    func bindKeyboardExpanded(_ expanded: Binding<Bool>) -> some View {
        #if canImport(UIKit)
        modifier(KeyboardExpandedBinder(expanded: expanded))
        #else
        self
        #endif
    }
}
