import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct GameView: View {
    @Environment(AppModel.self) private var app
    @State private var draft = ""
    @State private var selectedPanel = 0
    @FocusState private var chatFocused: Bool

    var body: some View {
        Group {
            if let session = app.game {
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
    var session: GameSession
    @Binding var draft: String
    @Binding var selectedPanel: Int
    var chatFocused: FocusState<Bool>.Binding
    var onLeave: () -> Void
    var onDetach: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GameHeader(session: session)
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
            GamePanelPicker(selectedPanel: $selectedPanel)
        }
        .background(UMTheme.bg.ignoresSafeArea())
        .toolbar(app.hideAppTabs ? .hidden : .automatic, for: .tabBar)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Leave", action: onLeave)
                    .foregroundStyle(UMTheme.mafia)
            }
        }
        .alert("Game", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
        .onChange(of: session.displaced) { _, displaced in
            if displaced { onDetach() }
        }
        .task { await RoleCatalog.shared.load() }
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

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(session.connected ? UMTheme.village : UMTheme.mafia)
                .frame(width: 8, height: 8)
            Text(session.setupName ?? session.gameType ?? "Game")
                .font(.headline)
                .lineLimit(1)
            if session.finished {
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
    @Binding var selectedPanel: Int
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 4) {
            tabBtn("Village", 1, "person.3")
            tabBtn("Chat", 0, "text.bubble")
            tabBtn("Act", 2, "hand.raised")
            hideBtn
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(UMTheme.card)
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

private struct ChatScrollPin: Equatable {
    var atBottom: Bool
    var atTop: Bool
    var contentH: CGFloat
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

    var body: some View {
        VStack(spacing: 0) {
            PhaseBar(session: session)
            ScrollViewReader { proxy in
                ScrollView {
                    let lines = session.displayedMessages.filter { showVotingLog || !$0.isVoteLog }
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
                    .padding(12)
                    .padding(.bottom, 8)
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
                    ChatScrollPin(atBottom: pinnedToLatest(geo), atTop: pinnedToTop(geo), contentH: geo.contentSize.height)
                } action: { old, pin in
                    if atTop != pin.atTop { atTop = pin.atTop }
                    if stickToBottom, pin.contentH > old.contentH + 1 {
                        return
                    }
                    if stickToBottom != pin.atBottom {
                        stickToBottom = pin.atBottom
                        if pin.atBottom { unreadCount = 0 }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if !stickToBottom {
                            Button {
                                unreadCount = 0
                                stickToBottom = true
                                jumpToLatest(proxy: proxy)
                            } label: {
                                Text(unreadCount > 0 ? "\(unreadCount) new messages" : "Go to latest message")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(UMTheme.blood, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 8)
                            .accessibilityLabel(unreadCount > 0 ? "\(unreadCount) new messages" : "Go to latest message")
                        }
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 8)
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
                        unreadCount = 0
                        jumpToLatestIfPinned(proxy: proxy)
                    } else if new > old {
                        unreadCount += new - old
                    }
                }
                .onChange(of: session.viewingPhaseId) { _, _ in
                    unreadCount = 0
                    stickToBottom = true
                    jumpToLatest(proxy: proxy)
                }
                .onAppear {
                    stickToBottom = true
                    jumpToLatest(proxy: proxy)
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
    @AppStorage("um.showTabButton") private var showTabButton = true
    @State private var keyboardExpanded = false

    var body: some View {
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
            .padding(10)
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
        .bindKeyboardExpanded($keyboardExpanded)
        .toolbar {
            if showTabButton, keyboardExpanded {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Tab") { _ = completeName() }
                    Spacer()
                }
            }
        }
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
                        size: 28
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
            size: 18
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
