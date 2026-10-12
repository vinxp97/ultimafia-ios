import SwiftUI

/// Web "strategies" for a setup: GET /api/strategy?setupId=… returns every guide (no paging),
/// already sorted by voteCount desc. We re-sort defensively and drop deleted / negative ones.
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
    var updatedAt: Double?
    var deleted: Bool?
    var author: Author?
}

extension APIClient {
    func setupGuides(setupId: String) async throws -> [SetupGuide] {
        let all: [SetupGuide] = try await get("strategy", query: ["setupId": setupId])
        return all
            .filter { $0.deleted != true && ($0.voteCount ?? 0) >= 0 }
            .sorted { (a, b) in
                let va = a.voteCount ?? 0, vb = b.voteCount ?? 0
                return va != vb ? va > vb : (a.updatedAt ?? 0) > (b.updatedAt ?? 0)
            }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if loading {
                        ProgressView().tint(UMTheme.blood).frame(maxWidth: .infinity).padding()
                    } else if let error {
                        Text(error).foregroundStyle(UMTheme.mafia)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ guide: SetupGuide) -> some View {
        let open = expanded.contains(guide.id)
        return VStack(alignment: .leading, spacing: 10) {
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
                    Label("\(guide.voteCount ?? 0)", systemImage: "arrow.up")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(UMTheme.muted)
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .foregroundStyle(UMTheme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Collapse guide" : "Expand guide")
            if open {
                Divider().overlay(UMTheme.line)
                UMMarkdownView(text: guide.content ?? "", roleGameType: gameType, otherRoles: otherRoles)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        await RoleCatalog.shared.load()
        do {
            guides = try await APIClient.shared.setupGuides(setupId: setupId)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
