import SwiftUI

/// Messages tab (hidden in games): Public chat (the site's home chat rooms) or Direct messages.
struct MessagesView: View {
    @Environment(AppModel.self) private var app
    @State private var store = UMChatStore.shared
    @State private var mode: Mode = .publicChat
    @State private var path: [String] = []
    @State private var composing = false

    enum Mode: String, CaseIterable, Identifiable {
        case publicChat = "Public chat", direct = "Direct messages"
        var id: String { rawValue }
    }

    init(mode: Mode = .publicChat) {
        _mode = State(initialValue: mode)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("Chat", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        if m == .direct, store.unreadDMCount > 0 {
                            Text("\(m.rawValue) (\(store.unreadDMCount))").tag(m)
                        } else {
                            Text(m.rawValue).tag(m)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                switch mode {
                case .publicChat: PublicChatPane(store: store)
                case .direct: DMListView(store: store)
                }
            }
            .background(UMTheme.bg.ignoresSafeArea())
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .direct {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel("New message")
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                DMThreadView(store: store, channelId: id)
            }
            .sheet(isPresented: $composing) {
                NewMessageView(store: store)
            }
            .onChange(of: store.focusChannelId) { _, id in
                guard let id else { return }
                mode = .direct
                composing = false
                path = [id]
                store.focusChannelId = nil
            }
            .onAppear {
                if let id = store.focusChannelId {
                    mode = .direct
                    path = [id]
                    store.focusChannelId = nil
                }
            }
        }
    }
}

// MARK: Public chat

private struct PublicChatPane: View {
    var store: UMChatStore
    @State private var roomId: String?
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            if store.rooms.count > 1 {
                Picker("Room", selection: Binding(get: { roomId ?? store.rooms.first?.id }, set: { roomId = $0 })) {
                    ForEach(store.rooms) { Text($0.name ?? "Room").tag(Optional($0.id)) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            }
            if !store.connected {
                ProgressView("Connecting to chat…").frame(maxHeight: .infinity)
            } else {
                ChatTranscript(store: store)
                ChatComposerBar(draft: $draft, placeholder: "Message public chat", disabled: false) {
                    store.send(draft)
                    draft = ""
                }
            }
        }
        .onAppear(perform: openRoom)
        .onChange(of: store.rooms) { _, _ in openRoom() }
        .onChange(of: roomId) { _, _ in openRoom() }
        .onDisappear { if let id = currentRoom { store.closeView(id) } }
    }

    private var currentRoom: String? { roomId ?? store.rooms.first?.id }

    private func openRoom() {
        guard let id = currentRoom, store.currentChannelId != id else { return }
        store.open(id)
    }
}

// MARK: DMs

private struct DMListView: View {
    var store: UMChatStore

    var body: some View {
        if store.directs.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 40)).foregroundStyle(UMTheme.muted)
                Text("No conversations yet").font(.headline)
                Text("Tap the pencil to message one or more players.")
                    .font(.subheadline).foregroundStyle(UMTheme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(store.directs) { ch in
                    NavigationLink(value: ch.id) {
                        HStack(spacing: 10) {
                            let others = ch.others(selfId: store.selfId)
                            UMAvatarView(userId: others.first?.id, hasAvatar: others.first?.avatar ?? false,
                                         name: others.first?.name ?? "", size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ch.title(selfId: store.selfId))
                                    .font(.body.weight(store.unread.contains(ch.id) ? .bold : .regular))
                                    .lineLimit(1)
                                if ch.lastMessageDate > .distantPast {
                                    Text(ch.lastMessageDate, style: .relative)
                                        .font(.caption).foregroundStyle(UMTheme.muted)
                                }
                            }
                            Spacer()
                            if store.unread.contains(ch.id) {
                                Circle().fill(UMTheme.blood).frame(width: 9, height: 9)
                            }
                        }
                    }
                    .listRowBackground(UMTheme.card)
                    .swipeActions {
                        Button("Close", role: .destructive) { store.closeDM(ch.id) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

struct DMThreadView: View {
    var store: UMChatStore
    var channelId: String
    @State private var draft = ""
    @State private var blocked: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            if !blocked.isEmpty {
                Label("\(blocked.joined(separator: ", ")) only accept\(blocked.count == 1 ? "s" : "") DMs from friends. The server will reject messages until they add you as a friend.",
                      systemImage: "person.badge.shield.checkmark")
                    .font(.footnote)
                    .foregroundStyle(UMTheme.mafia)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(UMTheme.card)
            }
            ChatTranscript(store: store)
            ChatComposerBar(draft: $draft, placeholder: "Message", disabled: !blocked.isEmpty || store.inGame) {
                store.send(draft)
                draft = ""
            }
        }
        .background(UMTheme.bg.ignoresSafeArea())
        .navigationTitle(store.channel(channelId)?.title(selfId: store.selfId) ?? "Message")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.open(channelId) }
        .onDisappear { store.closeView(channelId) }
        .task(id: channelId) {
            guard let ch = store.channel(channelId) else { return }
            var names: [String] = []
            for u in ch.others(selfId: store.selfId) where await UMChatStore.dmBlockReason(for: u.id) != nil {
                names.append(u.name)
            }
            blocked = names
        }
    }
}

// MARK: New message (multi-recipient)

struct NewMessageView: View {
    var store: UMChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var recipients: [UMChatUser] = []
    @State private var blockReasons: [String: String] = [:]
    @State private var query = ""
    @State private var results: [UMChatUser] = []
    @State private var searching = false
    @State private var text = ""
    @FocusState private var queryFocused: Bool

    private var canSend: Bool {
        !recipients.isEmpty && blockReasons.isEmpty && !store.inGame
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                RecipientChips(recipients: recipients, blockReasons: blockReasons) { u in
                    recipients.removeAll { $0.id == u.id }
                    blockReasons[u.id] = nil
                }
                HStack {
                    Text("To:").foregroundStyle(UMTheme.muted)
                    TextField("Type a name", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($queryFocused)
                        .onSubmit { if let best = results.first { add(best) } }
                    if searching { ProgressView().controlSize(.small) }
                }
                .padding(12)
                .background(UMTheme.card)
                if !query.isEmpty {
                    List(results) { u in
                        Button { add(u) } label: {
                            HStack {
                                UMAvatarView(userId: u.id, hasAvatar: u.avatar, name: u.name, size: 28)
                                Text(u.name).foregroundStyle(.white)
                                Spacer()
                                if u.id == results.first?.id {
                                    Text("Return to add").font(.caption2).foregroundStyle(UMTheme.muted)
                                }
                            }
                        }
                        .listRowBackground(u.id == results.first?.id ? UMTheme.elevated : UMTheme.card)
                    }
                    .scrollContentBackground(.hidden)
                } else {
                    if !blockReasons.isEmpty {
                        Text(blockReasons.keys.compactMap { id in recipients.first { $0.id == id }?.name }
                            .joined(separator: ", ") + " only accept DMs from friends.")
                            .font(.footnote).foregroundStyle(UMTheme.mafia).padding(12)
                    }
                    TextField("Message", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .padding(12)
                        .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 12))
                        .padding(12)
                    Spacer()
                }
            }
            .background(UMTheme.bg.ignoresSafeArea())
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        store.startDM(userIds: recipients.map(\.id), firstMessage: text)
                        dismiss()
                    }
                    .disabled(!canSend)
                }
            }
            .onAppear { queryFocused = true }
            // Real-time lookup, debounced like the site's user search.
            .task(id: query) {
                let q = query
                guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                searching = true
                let found = await UMChatStore.searchUsers(q)
                guard !Task.isCancelled else { return }
                searching = false
                let chosen = Set(recipients.map(\.id))
                results = found.filter { $0.id != store.selfId && !chosen.contains($0.id) }
            }
        }
    }

    private func add(_ u: UMChatUser) {
        guard !recipients.contains(where: { $0.id == u.id }) else { return }
        recipients.append(u)
        query = ""
        results = []
        Task {
            if let reason = await UMChatStore.dmBlockReason(for: u.id) { blockReasons[u.id] = reason }
        }
    }
}

private struct RecipientChips: View {
    var recipients: [UMChatUser]
    var blockReasons: [String: String]
    var onRemove: (UMChatUser) -> Void

    var body: some View {
        if !recipients.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(recipients) { u in
                        let blocked = blockReasons[u.id] != nil
                        Button { onRemove(u) } label: {
                            HStack(spacing: 4) {
                                if blocked { Image(systemName: "lock.fill").font(.caption2) }
                                Text(u.name).font(.subheadline.weight(.semibold))
                                Image(systemName: "xmark").font(.caption2)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(blocked ? UMTheme.mafia.opacity(0.3) : UMTheme.blood.opacity(0.3), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(u.name)\(blocked ? ", only accepts DMs from friends" : "")")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }
}

// MARK: Shared pieces

private struct ChatTranscript: View {
    var store: UMChatStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if store.hasMoreHistory && !store.messages.isEmpty {
                        Button("Load earlier") { store.loadOlder() }
                            .font(.caption).frame(maxWidth: .infinity)
                    }
                    ForEach(store.messages) { m in
                        HStack(alignment: .top, spacing: 8) {
                            UMAvatarView(userId: m.sender.id, hasAvatar: m.sender.avatar, name: m.sender.name, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(m.sender.name).font(.subheadline.weight(.semibold))
                                    Text(m.date, style: .time).font(.caption2).foregroundStyle(UMTheme.muted)
                                }
                                Text(m.content).font(.body).textSelection(.enabled)
                            }
                        }
                        .id(m.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: store.messages.last?.id) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
            .onAppear { if let id = store.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
        }
        .overlay(alignment: .top) {
            if let err = store.lastError {
                Text(err).font(.footnote).padding(8)
                    .background(UMTheme.mafia.opacity(0.9), in: Capsule())
                    .padding(.top, 6)
                    .onTapGesture { store.lastError = nil }
                    .task { try? await Task.sleep(for: .seconds(4)); store.lastError = nil }
            }
        }
    }
}

private struct ChatComposerBar: View {
    @Binding var draft: String
    var placeholder: String
    var disabled: Bool
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 18))
                .onChange(of: draft) { _, v in if v.count > UMConfig.maxChatLength { draft = String(v.prefix(UMConfig.maxChatLength)) } }
                .onSubmit(onSend)
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(disabled || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send")
        }
        .disabled(disabled)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(UMTheme.bg)
    }
}

/// You tab: DM notification options (client-side) + game-invite placeholder.
struct DMNotificationSettingsSection: View {
    @AppStorage(UMDMNotify.enabledKey) private var enabled = false
    @AppStorage(UMDMNotify.soundKey) private var sound = true
    @AppStorage(UMDMNotify.previewKey) private var preview = true
    @AppStorage(UMDMNotify.invitesKey) private var invites = false
    @State private var denied = false

    var body: some View {
        Section {
            Toggle("Direct message alerts", isOn: $enabled)
                .onChange(of: enabled) { _, on in
                    guard on else { return }
                    UMDMNotify.requestPermission { granted in
                        if !granted { enabled = false; denied = true }
                    }
                }
                .listRowBackground(UMTheme.card)
            Toggle("Sound", isOn: $sound).disabled(!enabled).listRowBackground(UMTheme.card)
            Toggle("Show preview", isOn: $preview).disabled(!enabled).listRowBackground(UMTheme.card)
            Toggle(isOn: $invites) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Game invites")
                    Text("Coming in a future update").font(.caption).foregroundStyle(UMTheme.muted)
                }
            }
            .disabled(true)
            .listRowBackground(UMTheme.card)
        } header: {
            Text("Notifications")
        } footer: {
            Text(denied
                 ? "Notifications are off for UltiMafia in iOS Settings. Turn them on there to get DM alerts."
                 : "Alerts arrive while the app is open or in the background, never during a game. Alerts with the app fully closed need server push (coming later).")
        }
    }
}
