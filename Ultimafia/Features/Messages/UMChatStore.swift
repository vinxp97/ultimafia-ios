import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// A user as the chat server sends it (redis basic info / populated members).
nonisolated struct UMChatUser: Identifiable, Hashable {
    var id: String
    var name: String
    var avatar: Bool

    init(id: String, name: String, avatar: Bool = false) {
        self.id = id
        self.name = name
        self.avatar = avatar
    }

    init?(_ any: Any?) {
        guard let o = any as? [String: Any], let id = o["id"] as? String else { return nil }
        self.init(id: id, name: o["name"] as? String ?? "?", avatar: (o["avatar"] as? Bool) ?? false)
    }
}

nonisolated struct UMChatMessage: Identifiable, Hashable {
    var id: String
    var channel: String
    var sender: UMChatUser
    var content: String
    var date: Date

    init(id: String, channel: String, sender: UMChatUser, content: String, date: Date) {
        self.id = id
        self.channel = channel
        self.sender = sender
        self.content = content
        self.date = date
    }

    init?(_ any: Any?) {
        guard let o = any as? [String: Any], let id = o["id"] as? String else { return nil }
        self.init(id: id,
                  channel: o["channel"] as? String ?? "",
                  sender: UMChatUser(o["sender"]) ?? UMChatUser(id: o["senderId"] as? String ?? "", name: "?"),
                  content: o["content"] as? String ?? "",
                  date: umChatDate(o["date"]) ?? Date())
    }
}

/// A chat channel: a public room (has a name) or a DM (members, id = md5 of sorted member ids).
nonisolated struct UMChatChannel: Identifiable, Hashable {
    var id: String
    var name: String?
    var isPublic: Bool
    var members: [UMChatUser]
    var lastMessageDate: Date
    /// Latest message preview for the DM list ("Name: text"), from newNotif.message / live messages.
    var snippet: String?

    init(id: String, name: String?, isPublic: Bool, members: [UMChatUser], lastMessageDate: Date) {
        self.id = id
        self.name = name
        self.isPublic = isPublic
        self.members = members
        self.lastMessageDate = lastMessageDate
    }

    init?(_ any: Any?) {
        guard let o = any as? [String: Any], let id = o["id"] as? String else { return nil }
        self.init(id: id,
                  name: o["name"] as? String,
                  isPublic: (o["public"] as? Bool) ?? false,
                  members: (o["members"] as? [Any] ?? []).compactMap(UMChatUser.init),
                  lastMessageDate: umChatDate(o["lastMessageDate"]) ?? .distantPast)
    }

    func others(selfId: String?) -> [UMChatUser] {
        let rest = members.filter { $0.id != selfId }
        return rest.isEmpty ? members : rest
    }

    func title(selfId: String?) -> String {
        if isPublic { return name ?? "Chat" }
        return others(selfId: selfId).map(\.name).joined(separator: ", ")
    }
}

/// Mongo dates arrive as ms numbers (messages) or ISO strings (channels).
nonisolated func umChatDate(_ any: Any?) -> Date? {
    if let d = any as? Double { return Date(timeIntervalSince1970: d / 1000) }
    if let n = any as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue / 1000) }
    if let s = any as? String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? Double(s).map { Date(timeIntervalSince1970: $0 / 1000) }
    }
    return nil
}

/// The site's chat (react_main pages/Chat, server modules/chat.js) over wss://ultimafia.com/chatSocket.
/// GET /api/chat/connect gives an auth token; the socket then sends `chatInfo` (rooms, open DMs,
/// unread chat notifs). The server tracks ONE current channel per socket (`getChannel`), so live
/// `message` events only arrive for the open channel; other DMs announce themselves with `newNotif`
/// (and `dateUpdate`/`newDirectChannel`), which carry no message text.
@MainActor
@Observable
final class UMChatStore {
    static let shared = UMChatStore()

    private(set) var rooms: [UMChatChannel] = []
    private(set) var directs: [UMChatChannel] = []
    private(set) var currentChannelId: String?
    private(set) var messages: [UMChatMessage] = []
    private(set) var unread: Set<String> = []
    private(set) var connected = false
    private(set) var hasMoreHistory = true
    var lastError: String?
    /// A DM to open (set by newDirectChannel focus/openDM or a notification tap).
    var focusChannelId: String?
    var selfId: String?

    /// In a game (seated or spectating): DMs are hidden, sending is blocked, notifications are muted.
    var inGame = false {
        didSet {
            guard inGame != oldValue else { return }
            if inGame { UMDMNotify.clearAll() }
            UMPush.reportInGame(inGame)
        }
    }

    var unreadDMCount: Int { directs.filter { unread.contains($0.id) }.count }

    @ObservationIgnored private let socket = GameSocket()
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFirstMessage: (ids: Set<String>, text: String)?

    func channel(_ id: String) -> UMChatChannel? {
        directs.first { $0.id == id } ?? rooms.first { $0.id == id }
    }

    func isDirect(_ id: String) -> Bool { directs.contains { $0.id == id } }

    // MARK: Connection

    func start(selfId: String?) {
        self.selfId = selfId
        guard !started, selfId != nil else { return }
        started = true
        Task { await connect() }
    }

    func stop() {
        started = false
        reconnectTask?.cancel()
        socket.disconnect()
        connected = false
        rooms = []; directs = []; messages = []; unread = []; currentChannelId = nil
    }

    private func connect() async {
        guard started else { return }
        do {
            let data = try await APIClient.shared.request("GET", path: "chat/connect", query: [:], body: nil)
            let t = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !t.isEmpty else { lastError = "Chat needs you to be signed in."; return }
            token = t
        } catch {
            UMDiag.log("chat", "connect token failed: \(error.localizedDescription)")
            scheduleReconnect()
            return
        }
        socket.onEvent = { [weak self] name, data in
            MainActor.assumeIsolated { self?.handle(name, data) }
        }
        socket.connect(port: "chatSocket")
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        guard started else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.connect()
        }
    }

    private func handle(_ name: String, _ data: Any?) {
        switch name {
        case "connected":
            if let token { socket.send("auth", object: token) }
        case "disconnected":
            connected = false
            scheduleReconnect()
        case "chatInfo":
            connected = true
            let o = data as? [String: Any] ?? [:]
            rooms = (o["rooms"] as? [Any] ?? []).compactMap(UMChatChannel.init)
            directs = sortDirects((o["directs"] as? [Any] ?? []).compactMap(UMChatChannel.init))
            for n in o["notifs"] as? [Any] ?? [] {
                if let id = (n as? [String: Any])?["channelId"] as? String { unread.insert(id) }
            }
            if let current = currentChannelId { socket.send("getChannel", object: current) }
        case "channel":
            guard let o = data as? [String: Any], let id = o["id"] as? String else { return }
            currentChannelId = id
            messages = (o["messages"] as? [Any] ?? []).compactMap(UMChatMessage.init)
            hasMoreHistory = messages.count >= 20
            if var ch = channel(id) {
                ch.members = (o["members"] as? [Any] ?? []).compactMap(UMChatUser.init)
                if !ch.isPublic { upsertDirect(ch) }
            }
            if let pending = pendingFirstMessage, isDirect(id),
               Set(channel(id)?.members.map(\.id) ?? []) == pending.ids {
                pendingFirstMessage = nil
                send(pending.text)
            }
        case "oldMessages":
            let older = (data as? [Any] ?? []).compactMap(UMChatMessage.init)
            hasMoreHistory = older.count >= 20
            messages.insert(contentsOf: older.filter { m in !messages.contains { $0.id == m.id } }, at: 0)
        case "message":
            guard let m = UMChatMessage(data) else { return }
            if m.channel == currentChannelId, !messages.contains(where: { $0.id == m.id }) {
                messages.append(m)
            }
            touch(m.channel, m.date)
            setSnippet(m.channel, sender: m.sender.name, text: m.content)
            // Open channel but app in the background: the server sends `message`, not `newNotif`.
            if isDirect(m.channel), m.sender.id != selfId, !UMDMNotify.isAppActive {
                UMDMNotify.post(channel: channel(m.channel), sender: m.sender.name, text: m.content,
                                selfId: selfId, inGame: inGame)
            }
        case "dateUpdate":
            if let o = data as? [String: Any], let ch = o["channel"] as? String {
                touch(ch, umChatDate(o["date"]) ?? Date())
            }
        case "newDirectChannel":
            guard let o = data as? [String: Any], let ch = UMChatChannel(o["channel"]) else { return }
            upsertDirect(ch)
            if (o["focus"] as? Bool) == true { focusChannelId = ch.id }
        case "openDM":
            if let id = data as? String { focusChannelId = id }
        case "newNotif":
            guard let o = data as? [String: Any], let n = o["notif"] as? [String: Any],
                  (n["isChat"] as? Bool) == true, let ch = n["channelId"] as? String else { return }
            unread.insert(ch)
            // DM notifs carry message {channelId, senderId, senderName, content (<=200), messageId}.
            let msg = o["message"] as? [String: Any]
            let senderName = msg?["senderName"] as? String
            let content = msg?["content"] as? String
            if let content { setSnippet(ch, sender: senderName, text: content); touch(ch, Date()) }
            if isDirect(ch) || !(rooms.contains { $0.id == ch }) {
                UMDMNotify.post(channel: channel(ch), sender: senderName, text: content, selfId: selfId,
                                inGame: inGame, channelId: ch)
            }
        case "messageDeleted":
            if let id = data as? String { messages.removeAll { $0.id == id } }
        case "error":
            lastError = data as? String ?? "Chat error."
        default:
            break
        }
    }

    private func sortDirects(_ list: [UMChatChannel]) -> [UMChatChannel] {
        list.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    private func upsertDirect(_ ch: UMChatChannel) {
        var list = directs.filter { $0.id != ch.id }
        var merged = ch
        if merged.members.isEmpty, let old = directs.first(where: { $0.id == ch.id }) { merged.members = old.members }
        list.append(merged)
        directs = sortDirects(list)
    }

    private func setSnippet(_ id: String, sender: String?, text: String) {
        guard let i = directs.firstIndex(where: { $0.id == id }) else { return }
        let selfName = directs[i].members.first { $0.id == selfId }?.name
        let who = (sender != nil && sender == selfName) ? "You" : sender
        directs[i].snippet = who.map { "\($0): \(text)" } ?? text
    }

    private func touch(_ id: String, _ date: Date) {
        if let i = directs.firstIndex(where: { $0.id == id }) {
            directs[i].lastMessageDate = date
            directs = sortDirects(directs)
        }
    }

    // MARK: Actions

    func open(_ id: String) {
        #if DEBUG
        if demo { currentChannelId = id; unread.remove(id); return }
        #endif
        if currentChannelId != id { messages = [] }
        currentChannelId = id
        unread.remove(id)
        UMDMNotify.clear(channelId: id)
        socket.send("getChannel", object: id)
        socket.send("readNotifsInChannel", object: id)
    }

    /// Leaving a chat screen: the server stops counting us as viewing it (so DMs notify again).
    func closeView(_ id: String) {
        guard currentChannelId == id else { return }
        socket.send("closedChat")
        currentChannelId = nil
    }

    func loadOlder() {
        guard let first = messages.first, hasMoreHistory else { return }
        socket.send("getOldMessages", object: Int(first.date.timeIntervalSince1970 * 1000))
    }

    /// Sends to the open channel. DMs are blocked while in a game.
    func send(_ text: String) {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(UMConfig.maxChatLength))
        guard !trimmed.isEmpty, let current = currentChannelId else { return }
        if isDirect(current) && inGame {
            lastError = "Direct messages are off while you're in a game."
            return
        }
        socket.send("sendMessage", object: trimmed)
    }

    /// New DM to one or more users: newDMChannel creates/opens the channel (id = md5 of sorted ids),
    /// then the first message goes out once that channel has loaded.
    func startDM(userIds: [String], firstMessage: String) {
        guard !inGame else { lastError = "Direct messages are off while you're in a game."; return }
        var ids = Set(userIds)
        if let selfId { ids.insert(selfId) }
        let text = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { pendingFirstMessage = (ids, text) }
        socket.send("newDMChannel", object: userIds)
    }

    func closeDM(_ id: String) {
        socket.send("closeDM", object: id)
        directs.removeAll { $0.id == id }
        unread.remove(id)
    }

    // MARK: Lookups (REST)

    /// The users-page search: GET /api/user/searchName?query= (prefix matches first, online first).
    static func searchUsers(_ query: String) async -> [UMChatUser] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty,
              let any = try? await APIClient.shared.jsonObject("user/searchName", query: ["query": q]),
              let arr = any as? [Any] else { return [] }
        return arr.compactMap(UMChatUser.init)
    }

    /// Server rule (modules/chat.js sendMessage): a member with settings.onlyFriendDMs only accepts
    /// DMs from users they have friended (Friend{userId: member, friendId: sender}). The profile's
    /// isFriend is the viewer's side of that pair, which is the best client-side signal.
    static func dmBlockReason(for userId: String) async -> String? {
        guard let p = try? await APIClient.shared.userProfile(userId) else { return nil }
        let settings = p["settings"] as? [String: Any] ?? [:]
        let only = (settings["onlyFriendDMs"] as? Bool) ?? ((settings["onlyFriendDMs"] as? String) == "true")
        let friend = (p["isFriend"] as? Bool) ?? false
        return only && !friend ? "only accepts DMs from friends" : nil
    }

    #if DEBUG
    @ObservationIgnored private var demo = false

    func loadDemo(selfId: String) {
        demo = true
        self.selfId = selfId
        let me = UMChatUser(id: selfId, name: "Vinman")
        let a = UMChatUser(id: "a", name: "Aspect"), b = UMChatUser(id: "b", name: "Pranay"), c = UMChatUser(id: "c", name: "Z")
        rooms = [UMChatChannel(id: "main", name: "Main", isPublic: true, members: [], lastMessageDate: .now)]
        directs = [
            UMChatChannel(id: "d1", name: nil, isPublic: false, members: [me, a], lastMessageDate: .now),
            UMChatChannel(id: "d2", name: nil, isPublic: false, members: [me, b, c], lastMessageDate: .now - 3600),
        ]
        unread = ["d1"]
        directs[0].snippet = "Aspect: gg, rematch?"
        directs[1].snippet = "Pranay: push is live on dev"
        currentChannelId = "main"
        let now = Date()
        messages = [
            UMChatMessage(id: "1", channel: "main", sender: a, content: "anyone up for a 7p?", date: now - 300),
            UMChatMessage(id: "2", channel: "main", sender: c, content: "hosting in a sec", date: now - 240),
            UMChatMessage(id: "3", channel: "main", sender: me, content: "I'm in", date: now - 60),
        ]
        connected = true
    }
    #endif
}
