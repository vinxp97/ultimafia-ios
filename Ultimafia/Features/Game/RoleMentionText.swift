import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct UMRoleMentionItem: Identifiable {
    static let scheme = "umrole"
    var id: String { name }
    var name: String
}

/// Styles role names inside already-parsed markdown the way chat does (EmoteText): yellow,
/// semibold, role icon in front, tappable. Tapping goes through the `umrole://` link, which
/// UMMarkdownView intercepts to open RoleDetailsSheet. Keeps normal text wrapping and markdown.
func umRoleMentionText(_ attr: AttributedString, gameType: String) -> Text {
    let plain = String(attr.characters)
    let hits = RoleCatalog.shared.mentions(in: plain, gameType: gameType)
    guard !hits.isEmpty else { return Text(attr) }

    func slice(_ lo: Int, _ hi: Int) -> AttributedString {
        let a = attr.index(attr.startIndex, offsetByCharacters: lo)
        let b = attr.index(attr.startIndex, offsetByCharacters: hi)
        return AttributedString(attr[a..<b])
    }

    var out = Text("")
    var cursor = 0
    for hit in hits {
        let lo = plain.distance(from: plain.startIndex, to: hit.range.lowerBound)
        let hi = plain.distance(from: plain.startIndex, to: hit.range.upperBound)
        guard lo >= cursor else { continue }
        if lo > cursor { out = Text("\(out)\(Text(slice(cursor, lo)))") }
        var mention = slice(lo, hi)
        mention.foregroundColor = UMTheme.roleMention
        mention.inlinePresentationIntent = .stronglyEmphasized
        let encoded = hit.name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? hit.name
        mention.link = URL(string: "\(UMRoleMentionItem.scheme)://\(encoded)")
        if let icon = umRoleIconImage(hit.name, gameType: gameType) {
            out = Text("\(out)\(Text(Image(uiImage: icon)).baselineOffset(-3)) ")
        }
        out = Text("\(out)\(Text(mention))")
        cursor = hi
    }
    if cursor < plain.count { out = Text("\(out)\(Text(slice(cursor, plain.count)))") }
    return out
}

/// Bundled role icon scaled for inline text. Remote-only icons are skipped (text still styled).
private func umRoleIconImage(_ name: String, gameType: String) -> UIImage? {
    let roleName = name.split(separator: ":").first.map(String.init) ?? name
    guard let url = RoleArt.roleURL(gameType: gameType, name: roleName), url.isFileURL,
          let image = UIImage(contentsOfFile: url.path) else { return nil }
    let side: CGFloat = 16
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
        image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
    }
}
