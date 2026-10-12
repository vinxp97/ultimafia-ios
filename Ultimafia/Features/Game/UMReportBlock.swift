import SwiftUI

/// Report / Block, mirroring the site:
/// - Report: web ReportDialog.jsx -> POST /api/report/send {game, user, rule, description?};
///   rules from GET /api/site/violations (data/violations.js `name`), validated server-side.
/// - Block: web Profile.jsx -> POST /api/user/block {user}; the route TOGGLES membership in
///   User.blockedUsers (routes/user.js:3647). Current list comes from GET /api/user/info `blockedUsers`.
enum UMModeration {
    static let contactEmail = "ultimafia.official@gmail.com"

    /// data/violations.js names (UltiMafia master @059db68); used if /site/violations fails.
    static let fallbackViolations = [
        "Personal Attacks & Harassment (PA)", "Intolerance", "Adult Content", "Instigation", "Hazing",
        "Outing of Personal Information (OPI)", "Coercion", "Impersonation",
        "Illegal Content & Activity (IC)", "Antagonization", "Game Throwing",
        "Game-Related Abandonment (GRA)", "Cheating", "Insufficient Participation (ISP)",
        "Outside of Game Information (OGI)", "Exploits",
    ]

    private struct Violation: Decodable { var name: String }

    static func loadViolations() async -> [String] {
        if let list: [Violation] = try? await APIClient.shared.get("site/violations"), !list.isEmpty {
            return list.map(\.name)
        }
        return fallbackViolations
    }

    static func sendReport(gameId: String?, userId: String, rule: String, description: String) async throws {
        var body: [String: Any] = ["user": userId, "rule": rule]
        if let gameId, !gameId.isEmpty { body["game"] = gameId }
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { body["description"] = d }
        try await APIClient.shared.postStatus("report/send", json: body)
    }

    /// Toggles block on the server, then mirrors the new state into `app.user`.
    @MainActor
    static func toggleBlock(userId: String, app: AppModel) async throws {
        guard !app.isSelf(userId: userId) else { throw UMError.message("You cannot block yourself.") }
        try await APIClient.shared.postStatus("user/block", json: ["user": userId])
        guard var u = app.user else { return }
        var list = u.blockedUsers ?? []
        if let i = list.firstIndex(of: userId) { list.remove(at: i) } else { list.append(userId) }
        u.blockedUsers = list
        app.user = u
        app.applyBlockFilterToLobby()
    }
}

extension AppModel {
    /// You, by every id we have: seat id, the player's account id vs the active session user,
    /// and (safety net for misaligned review data) the account name.
    func isSelf(_ player: GamePlayer, selfSeatId: String? = nil) -> Bool {
        if let seat = selfSeatId, !seat.isEmpty, player.id == seat { return true }
        if let me = user?.id, !me.isEmpty {
            if player.userId == me || player.id == me { return true }
        }
        if let myName = user?.name, !myName.isEmpty,
           player.name.caseInsensitiveCompare(myName) == .orderedSame { return true }
        return false
    }

    func isSelf(userId: String?) -> Bool {
        guard let userId, !userId.isEmpty, let me = user?.id else { return false }
        return userId == me
    }

    func isBlocked(_ userId: String?) -> Bool {
        guard let userId else { return false }
        return user?.blockedUsers?.contains(userId) ?? false
    }
}

/// Report + Block/Unblock for one player, shown under their Village row post-game.
struct UMPlayerModerationBar: View {
    var player: GamePlayer
    var gameId: String
    @Environment(AppModel.self) private var app
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var busy = false
    @State private var resultMessage: String?

    var body: some View {
        if app.isSelf(player) || app.isSelf(userId: player.userId) {
            EmptyView()
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        let blocked = app.isBlocked(player.userId)
        HStack(spacing: 10) {
            Button { showReport = true } label: {
                Label("Report", systemImage: "exclamationmark.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(UMTheme.blood)
            Button { confirmBlock = true } label: {
                Label(blocked ? "Unblock" : "Block", systemImage: blocked ? "person.crop.circle.badge.checkmark" : "nosign")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(blocked ? .gray : .orange)
            .disabled(busy)
        }
        .font(.subheadline.weight(.semibold))
        .sheet(isPresented: $showReport) {
            UMReportSheet(player: player, gameId: gameId)
        }
        .alert(blocked ? "Unblock \(player.name)?" : "Block \(player.name)?", isPresented: $confirmBlock) {
            Button("Cancel", role: .cancel) {}
            Button(blocked ? "Unblock" : "Block", role: blocked ? nil : .destructive) { toggle() }
        } message: {
            Text(blocked ? "They'll be able to interact with you again." : "This uses your Ultimafia block list, the same one as the website.")
        }
        .alert("Block", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func toggle() {
        guard let uid = player.userId, !app.isSelf(player), !app.isSelf(userId: uid) else { return }
        let wasBlocked = app.isBlocked(uid)
        busy = true
        Task {
            do {
                try await UMModeration.toggleBlock(userId: uid, app: app)
                resultMessage = wasBlocked ? "User unblocked." : "User blocked."
            } catch {
                resultMessage = UMFriendlyError.message(for: error)
            }
            busy = false
        }
    }
}

struct UMReportSheet: View {
    var player: GamePlayer
    var gameId: String
    @Environment(AppModel.self) private var app
    private var isSelfTarget: Bool { app.isSelf(player) || app.isSelf(userId: player.userId) }
    @Environment(\.dismiss) private var dismiss
    @State private var violations: [String] = []
    @State private var rule = ""
    @State private var details = ""
    @State private var confirm = false
    @State private var sending = false
    @State private var errorText: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Please provide as much detail as possible when reporting rule or policy violations.")
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Game", value: gameId)
                    LabeledContent("User Reported", value: player.name)
                }
                Section("Rule Broken") {
                    if violations.isEmpty {
                        ProgressView()
                    } else {
                        Picker("Rule Broken", selection: $rule) {
                            Text("Select a rule").tag("")
                            ForEach(violations, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }
                Section("Description (Optional)") {
                    TextField("What happened?", text: $details, axis: .vertical)
                        .lineLimit(4...10)
                }
                Section {
                    Button {
                        confirm = true
                    } label: {
                        HStack {
                            Spacer()
                            if sending { ProgressView() } else { Text("Submit Report").bold() }
                            Spacer()
                        }
                    }
                    .disabled(rule.isEmpty || sending || player.userId == nil || isSelfTarget)
                } footer: {
                    if let e = errorText {
                        Text(e).foregroundStyle(.red)
                    }
                }
                Section {
                    contactLine
                }
            }
            .navigationTitle("File a Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .umKeyboardDismissBar()
            .task { if violations.isEmpty { violations = await UMModeration.loadViolations() } }
            .alert("Submit this report?", isPresented: $confirm) {
                Button("Cancel", role: .cancel) {}
                Button("Submit") { submit() }
            } message: {
                Text("\(player.name) · \(rule)")
            }
            .alert("Report sent", isPresented: $sent) {
                Button("OK") { dismiss() }
            } message: {
                Text("Thank you — your report was delivered to moderators.")
            }
        }
    }

    private var contactLine: some View {
        let email = UMModeration.contactEmail
        var s = AttributedString("For any urgent inquiries, please contact \(email)")
        if let r = s.range(of: email) {
            s[r].link = URL(string: "mailto:\(email)")
            s[r].underlineStyle = .single
        }
        return Text(s).font(.footnote).foregroundStyle(.secondary)
    }

    private func submit() {
        guard let uid = player.userId else { return }
        guard !isSelfTarget else { errorText = "You can't report yourself."; return }
        sending = true
        errorText = nil
        Task {
            do {
                try await UMModeration.sendReport(gameId: gameId, userId: uid, rule: rule, description: details)
                sent = true
            } catch {
                errorText = UMFriendlyError.message(for: error)
            }
            sending = false
        }
    }
}
