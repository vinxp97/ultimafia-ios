import SwiftUI

/// Web "strategies" for a setup: GET /api/strategy?setupId=… returns every guide (no paging),
/// already sorted by voteCount desc (routes/strategy.js: deleted, voteCount desc, updatedAt desc,
/// createdAt desc) with your own `vote` (1 / -1 / 0) per guide. We re-sort defensively and drop
/// deleted / negative ones at load.
/// Voting: POST /api/votes {item, itemType:"strategy", direction:±1}; same direction again removes
/// the vote, the other direction switches it (routes/votes.js; voteCount ±1 / ±2).
struct SetupGuide: Decodable, Identifiable, Hashable {
    struct Author: Decodable, Hashable {
        var id: String?
        var name: String?
        var avatar: Bool?
    }
    var id: String
    var title: String?
    var content: String?
    var voteCount: Int?
    /// Your vote: 1, -1, or 0 (server voteMap).
    var vote: Int?
    var updatedAt: Double?
    var deleted: Bool?
    var author: Author?
}

extension APIClient {
    func setupGuides(setupId: String) async throws -> [SetupGuide] {
        let all: [SetupGuide] = try await get("strategy", query: ["setupId": setupId])
        return all
            .filter { $0.deleted != true && ($0.voteCount ?? 0) >= 0 }
            .sorted(by: SetupGuide.ranks)
    }
}

extension SetupGuide {
    nonisolated static func ranks(_ a: SetupGuide, _ b: SetupGuide) -> Bool {
        let va = a.voteCount ?? 0, vb = b.voteCount ?? 0
        return va != vb ? va > vb : (a.updatedAt ?? 0) > (b.updatedAt ?? 0)
    }

    /// Local result of voting `direction` (same arrow removes, other arrow switches).
    func applyingVote(_ direction: Int) -> SetupGuide {
        var g = self
        let old = vote ?? 0
        let new = old == direction ? 0 : direction
        g.vote = new
        g.voteCount = (voteCount ?? 0) + (new - old)
        return g
    }
}

struct GuidesView: View {
    let setupId: String
    let setupName: String?
    let gameType: String
    let otherRoles: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var guides: [SetupGuide] = []
    @State private var expanded: Set<String> = []
    @State private var loading = true
    @State private var error: String?
    @State private var voting: Set<String> = []
    @State private var voteError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if loading {
                        ProgressView().tint(UMTheme.blood).frame(maxWidth: .infinity).padding()
                    } else if let error {
                        UMLoadErrorView(title: "Couldn't load guides.", detail: error) {
                            Task { await load() }
                        }
                    } else if guides.isEmpty {
                        Text("No guides for this setup yet.").foregroundStyle(UMTheme.muted)
                            .frame(maxWidth: .infinity).padding()
                    }
                    ForEach(guides) { guide in row(guide) }
                }
                .padding(16)
            }
            .background(UMTheme.bg.ignoresSafeArea())
            .navigationTitle(setupName.map { "Guides · \($0)" } ?? "Guides")
            .umInlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
            .alert("Vote failed", isPresented: Binding(get: { voteError != nil }, set: { if !$0 { voteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(voteError ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ guide: SetupGuide) -> some View {
        let open = expanded.contains(guide.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
            voteControl(guide)
            Button {
                withAnimation(.snappy) {
                    if open { expanded.remove(guide.id) } else { expanded.insert(guide.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    UMAvatarView(userId: guide.author?.id, hasAvatar: guide.author?.avatar ?? false,
                                 name: guide.author?.name ?? "", size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guide.title?.isEmpty == false ? guide.title! : "Untitled")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Text(guide.author?.name ?? "Unknown")
                            .font(.caption).foregroundStyle(UMTheme.muted)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .foregroundStyle(UMTheme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Collapse guide" : "Expand guide")
            }
            if open {
                Divider().overlay(UMTheme.line)
                UMMarkdownView(text: guide.content ?? "", roleGameType: gameType, otherRoles: otherRoles)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func voteControl(_ guide: SetupGuide) -> some View {
        let vote = guide.vote ?? 0
        return VStack(spacing: 2) {
            Button { castVote(guide.id, 1) } label: {
                Image(systemName: vote == 1 ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(vote == 1 ? UMTheme.blood : UMTheme.muted)
                    .frame(width: 28, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(vote == 1 ? "Remove upvote" : "Upvote")
            Text("\(guide.voteCount ?? 0)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(vote == 1 ? UMTheme.blood : (vote == -1 ? Color.cyan : .white))
                .contentTransition(.numericText())
            Button { castVote(guide.id, -1) } label: {
                Image(systemName: vote == -1 ? "arrowtriangle.down.fill" : "arrowtriangle.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(vote == -1 ? Color.cyan : UMTheme.muted)
                    .frame(width: 28, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(vote == -1 ? "Remove downvote" : "Downvote")
        }
        .disabled(voting.contains(guide.id))
    }

    /// Optimistic: update + re-sort now, roll back on failure. Server returns the new direction.
    private func castVote(_ id: String, _ direction: Int) {
        guard !voting.contains(id), let idx = guides.firstIndex(where: { $0.id == id }) else { return }
        let before = guides[idx]
        voting.insert(id)
        withAnimation(.snappy) {
            guides[idx] = before.applyingVote(direction)
            guides.sort(by: SetupGuide.ranks)
        }
        Task {
            defer { voting.remove(id) }
            do {
                let serverVote = try await APIClient.shared.voteItem(item: id, itemType: "strategy", direction: direction)
                if let i = guides.firstIndex(where: { $0.id == id }), (guides[i].vote ?? 0) != serverVote {
                    // Server disagrees (e.g. stale vote state): trust its direction.
                    withAnimation(.snappy) {
                        var g = guides[i]
                        g.voteCount = (before.voteCount ?? 0) + (serverVote - (before.vote ?? 0))
                        g.vote = serverVote
                        guides[i] = g
                        guides.sort(by: SetupGuide.ranks)
                    }
                }
            } catch {
                if let i = guides.firstIndex(where: { $0.id == id }) {
                    withAnimation(.snappy) {
                        guides[i] = before
                        guides.sort(by: SetupGuide.ranks)
                    }
                }
                voteError = UMFriendlyError.message(for: error)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        await RoleCatalog.shared.load()
        do {
            guides = try await APIClient.shared.setupGuides(setupId: setupId)
            error = nil
        } catch {
            self.error = UMFriendlyError.message(for: error)
        }
    }
}
