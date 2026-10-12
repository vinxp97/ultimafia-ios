import SwiftUI

struct FlowWrap: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? 0, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (sub, item) in zip(subviews, result.items) {
            sub.place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(item.size)
            )
        }
    }

    private struct Item {
        var origin: CGPoint
        var size: CGSize
    }

    private func arrange(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, items: [Item]) {
        let width = maxWidth > 0 ? maxWidth : .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var maxX: CGFloat = 0
        var items: [Item] = []
        for sub in subviews {
            let available = width.isFinite ? max(width - x, 0) : .infinity
            var size = sub.sizeThatFits(ProposedViewSize(width: available, height: nil))
            if x > 0, width.isFinite, size.width > available + 0.5 {
                y += rowH + spacing
                x = 0
                rowH = 0
                size = sub.sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            items.append(Item(origin: CGPoint(x: x, y: y), size: size))
            maxX = max(maxX, x + size.width)
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
        let usedWidth = width.isFinite ? width : maxX
        return (CGSize(width: usedWidth, height: y + rowH), items)
    }
}

struct EmoteText: View {
    let text: String
    var color: Color = .white
    var italic: Bool = false
    var customEmotes: [String: String] = [:]
    var customStickers: [String: String] = [:]
    var system: Bool = false
    var emoteSize: CGFloat = 20
    var players: [GamePlayer] = []
    var gameType: String = ""
    var otherRoles: [String] = []
    var roleColor: Color = UMTheme.roleMention

    @State private var selectedRole: MentionedRole?

    private struct MentionedRole: Identifiable {
        var id: String { name }
        var name: String
    }

    private struct Piece: Identifiable {
        let id: Int
        let text: String?
        let url: URL?
        let large: Bool
        let player: GamePlayer?
        let role: String?
    }

    var body: some View {
        let catalog = RoleCatalog.shared
        let _ = catalog.isReady
        let pieces = tokenize()
        FlowWrap(spacing: 3) {
            ForEach(pieces) { piece in
                pieceView(piece)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .sheet(item: $selectedRole) { mention in
            RoleDetailsSheet(
                roleRaw: mention.name,
                gameType: gameType.isEmpty ? "Mafia" : gameType,
                otherRoles: otherRoles
            )
        }
    }

    @ViewBuilder
    private func pieceView(_ piece: Piece) -> some View {
        if let player = piece.player {
            UMAvatarView(player: player, size: emoteSize)
                .offset(y: -1)
        } else if let role = piece.role {
            Button {
                selectedRole = MentionedRole(name: role)
            } label: {
                HStack(spacing: 3) {
                    RoleIconView(role: role, gameType: gameType.isEmpty ? "Mafia" : gameType, size: max(14, emoteSize - 2))
                    Text(piece.text ?? role)
                        .font((italic ? Font.body.italic() : Font.body).weight(.semibold))
                        .foregroundStyle(roleColor)
                }
                .fixedSize()
            }
            .buttonStyle(.plain)
        } else if let url = piece.url {
            AnimatedWebPView(url: url, showsPlaceholder: false, fitHeight: piece.large ? 28 : emoteSize)
                .fixedSize()
        } else {
            Text(piece.text ?? "")
                .font(italic ? .body.italic() : .body)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tokenize() -> [Piece] {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let emoteOnly = !words.isEmpty && words.allSatisfy { $0.isEmpty || mediaURL(for: $0) != nil }
        var out: [Piece] = []
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            appendText(buffer, to: &out)
            buffer = ""
        }
        for (i, word) in words.enumerated() {
            if word.isEmpty {
                buffer += (i == words.count - 1 ? "" : " ")
                continue
            }
            if let player = percentPlayer(for: word) {
                flush()
                out.append(Piece(id: out.count, text: nil, url: nil, large: false, player: player, role: nil))
            } else if let url = mediaURL(for: word) {
                flush()
                out.append(Piece(id: out.count, text: nil, url: url, large: emoteOnly, player: nil, role: nil))
            } else {
                if !buffer.isEmpty { buffer += " " }
                buffer += word
            }
        }
        flush()
        return out
    }

    private func appendText(_ s: String, to out: inout [Piece]) {
        let type = gameType.isEmpty ? "Mafia" : gameType
        let hits = RoleCatalog.shared.mentions(in: s, gameType: type)
        if hits.isEmpty {
            out.append(Piece(id: out.count, text: s, url: nil, large: false, player: nil, role: nil))
            return
        }
        var cursor = s.startIndex
        for hit in hits {
            if cursor < hit.range.lowerBound {
                out.append(Piece(id: out.count, text: String(s[cursor..<hit.range.lowerBound]), url: nil, large: false, player: nil, role: nil))
            }
            out.append(Piece(id: out.count, text: String(s[hit.range]), url: nil, large: false, player: nil, role: hit.name))
            cursor = hit.range.upperBound
        }
        if cursor < s.endIndex {
            out.append(Piece(id: out.count, text: String(s[cursor...]), url: nil, large: false, player: nil, role: nil))
        }
    }

    private func percentPlayer(for word: String) -> GamePlayer? {
        guard word.count > 1, word.hasPrefix("%") else { return nil }
        let name = String(word.dropFirst())
        if let exact = players.first(where: { $0.name == name }) { return exact }
        let lower = name.lowercased()
        let hits = players.filter { $0.name.lowercased() == lower }
        return hits.count == 1 ? hits[0] : nil
    }

    private func mediaURL(for word: String) -> URL? {
        let token = word.lowercased()
        if let url = UMSiteEmote.url(forToken: token) { return url }
        if system { return nil }
        if let path = customStickers[token] ?? customEmotes[token] {
            return UMMediaURL.resolve(path)
        }
        return nil
    }
}
