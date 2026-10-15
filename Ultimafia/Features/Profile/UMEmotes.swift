import Foundation
import SwiftUI
import UIKit

enum UMEmotes {
    struct Info {
        var file: String
        var ext: String
        var url: URL {
            URL(string: "https://raw.githubusercontent.com/UltiMafia/Ultimafia/master/react_main/src/images/emotes/\(file).\(ext)")!
        }
    }

    static let all: [String: Info] = [
        ";_;": Info(file: "cry", ext: "webp"),
        ";)": Info(file: "wink", ext: "webp"),
        ":(": Info(file: "sad", ext: "webp"),
        ":)": Info(file: "happy", ext: "webp"),
        ":o": Info(file: "surprised", ext: "webp"),
        ":p": Info(file: "tongue", ext: "webp"),
        "-_-": Info(file: "expressionless", ext: "webp"),
        ":|": Info(file: "neutral", ext: "webp"),
        ":3": Info(file: "candy", ext: "webp"),
        ":wink:": Info(file: "wink", ext: "webp"),
        ":zzz:": Info(file: "zzz", ext: "webp"),
        ">:(": Info(file: "frown", ext: "webp"),
        "<3": Info(file: "heart", ext: "webp"),
        "-@": Info(file: "jack", ext: "webp"),
        ":christmas:": Info(file: "christmas", ext: "webp"),
        ":cookie:": Info(file: "cookie", ext: "webp"),
        ":star:": Info(file: "star", ext: "webp"),
        ":rose:": Info(file: "rose", ext: "webp"),
        ":santa:": Info(file: "santa", ext: "webp"),
        ":candycane:": Info(file: "candycane", ext: "webp"),
        ":bats:": Info(file: "bats", ext: "webp"),
        ":boar:": Info(file: "boar", ext: "webp"),
        ":cat:": Info(file: "cat", ext: "webp"),
        ":@": Info(file: "cthulhu", ext: "webp"),
        ":bump:": Info(file: "bump", ext: "webp"),
        ":bunny:": Info(file: "bunny", ext: "webp"),
        ":cake:": Info(file: "cake", ext: "webp"),
        ":cupcake:": Info(file: "cupcake", ext: "webp"),
        ":doge:": Info(file: "doge", ext: "webp"),
        ":rainbowdoge:": Info(file: "rainbowdoge", ext: "webp"),
        ":rawr:": Info(file: "rawr", ext: "webp"),
        ":angel:": Info(file: "angel", ext: "png"),
        ":chefufu:": Info(file: "chefufu", ext: "png"),
        ":chtfulfu:": Info(file: "chtfulfu", ext: "png"),
        ":flufu:": Info(file: "flufu", ext: "png"),
        ":fufool:": Info(file: "fufool", ext: "png"),
        ":fufunky:": Info(file: "fufunky", ext: "png"),
        ":fufuzela:": Info(file: "fufuzela", ext: "png"),
        ":glad:": Info(file: "glad", ext: "png"),
        ":knifufu:": Info(file: "knifufu", ext: "png"),
        ":leafufu:": Info(file: "leafufu", ext: "png"),
        ":beefufu:": Info(file: "beefufu", ext: "png"),
        ":satan:": Info(file: "satan", ext: "png"),
        ":sleepy:": Info(file: "sleepy", ext: "png"),
        ":waifufu:": Info(file: "waifufu", ext: "png"),
        ":wat:": Info(file: "wat", ext: "png"),
        ":winky:": Info(file: "winky", ext: "png"),
        ":fufu:": Info(file: "fufu", ext: "webp"),
        ":fufunb:": Info(file: "fufunb", ext: "webp"),
        ":fufubi:": Info(file: "fufubi", ext: "webp"),
        ":fufulesbian:": Info(file: "fufulesbian", ext: "webp"),
        ":fufutrans:": Info(file: "fufutrans", ext: "webp"),
        ":omg:": Info(file: "omg", ext: "webp"),
        ":icry:": Info(file: "icry", ext: "webp"),
        ":gay:": Info(file: "gay", ext: "webp"),
        ":fox:": Info(file: "fox", ext: "webp"),
        ":ghost:": Info(file: "ghost", ext: "webp"),
        ":horse:": Info(file: "horse", ext: "webp"),
        ":lion:": Info(file: "lion", ext: "webp"),
        ":mermaid:": Info(file: "mermaid", ext: "webp"),
        ":panda:": Info(file: "panda", ext: "webp"),
        ":penguin:": Info(file: "penguin", ext: "webp"),
        ":pizza:": Info(file: "pizza", ext: "webp"),
        ":rainbow:": Info(file: "rainbow", ext: "webp"),
        ":sandbox:": Info(file: "sandbox", ext: "webp"),
        ":snowman:": Info(file: "snowman", ext: "webp"),
        ":sheep:": Info(file: "sheep", ext: "webp"),
        ":shotgun:": Info(file: "shotgun", ext: "webp"),
        ":snake:": Info(file: "snake", ext: "webp"),
        ":tiger:": Info(file: "tiger", ext: "webp"),
        ":unicorn:": Info(file: "unicorn", ext: "webp"),
        ":werewolf:": Info(file: "werewolf", ext: "webp"),
        ":wolf:": Info(file: "wolf", ext: "webp"),
        ":hammer:": Info(file: "hammer", ext: "webp"),
        ":message:": Info(file: "message", ext: "webp"),
        ":rip:": Info(file: "rip", ext: "webp"),
        ":system:": Info(file: "system", ext: "webp"),
        ":will:": Info(file: "will", ext: "webp"),
        ":armor:": Info(file: "armor", ext: "webp"),
        ":armor2:": Info(file: "armor2", ext: "webp"),
        ":bread:": Info(file: "bread", ext: "webp"),
        ":bread2:": Info(file: "bread2", ext: "webp"),
        ":beer:": Info(file: "beer", ext: "webp"),
        ":bomb:": Info(file: "bomb", ext: "webp"),
        ":cat2:": Info(file: "cat2", ext: "webp"),
        ":candle:": Info(file: "candle", ext: "webp"),
        ":crystal:": Info(file: "crystal", ext: "webp"),
        ":crystal2:": Info(file: "crystal2", ext: "webp"),
        ":doll:": Info(file: "doll", ext: "webp"),
        ":doll2:": Info(file: "doll2", ext: "webp"),
        ":dynamite:": Info(file: "dynamite", ext: "webp"),
        ":gun:": Info(file: "gun", ext: "webp"),
        ":gun2:": Info(file: "gun2", ext: "webp"),
        ":gun3:": Info(file: "gun3", ext: "webp"),
        ":gun4:": Info(file: "gun4", ext: "webp"),
        ":gunfab:": Info(file: "gunfab", ext: "webp"),
        ":key:": Info(file: "key", ext: "webp"),
        ":knife:": Info(file: "knife", ext: "webp"),
        ":knife2:": Info(file: "knife2", ext: "webp"),
        ":match:": Info(file: "match", ext: "webp"),
        ":snowball:": Info(file: "snowball", ext: "webp"),
        ":timebomb:": Info(file: "timebomb", ext: "webp"),
        ":yuzu:": Info(file: "yuzu", ext: "webp"),
        ":carol:": Info(file: "carol", ext: "webp"),
        ":carol2:": Info(file: "carol2", ext: "webp"),
        ":dream:": Info(file: "dream", ext: "webp"),
        ":invest:": Info(file: "invest", ext: "webp"),
        ":journ:": Info(file: "journ", ext: "webp"),
        ":law:": Info(file: "law", ext: "webp"),
        ":loud:": Info(file: "loud", ext: "webp"),
        ":snoop:": Info(file: "snoop", ext: "webp"),
        ":track:": Info(file: "track", ext: "webp"),
        ":visited:": Info(file: "visited", ext: "webp"),
        ":watch:": Info(file: "watch", ext: "webp"),
        ":love:": Info(file: "love", ext: "webp"),
        ":love2:": Info(file: "love2", ext: "webp"),
        ":hb:": Info(file: "heartbroken", ext: "webp"),
        ":insane:": Info(file: "insane", ext: "webp"),
        ":sane:": Info(file: "sane", ext: "webp"),
        ":invincible:": Info(file: "invincible", ext: "webp"),
        ":blood:": Info(file: "blood", ext: "webp"),
        ":veg:": Info(file: "veg", ext: "webp"),
        ":exit:": Info(file: "exit", ext: "webp"),
        ":flagblue:": Info(file: "flagblue", ext: "webp"),
        ":flagblack:": Info(file: "flagblack", ext: "webp"),
        ":flagyellow:": Info(file: "flagyellow", ext: "webp"),
        ":mistletoe:": Info(file: "mistletoe", ext: "webp"),
        ":anon:": Info(file: "anon", ext: "webp"),
        ":bible:": Info(file: "bible", ext: "webp"),
        ":dumbbell:": Info(file: "dumbbell", ext: "webp"),
        ":handcuff:": Info(file: "handcuff", ext: "webp"),
        ":mask:": Info(file: "mask", ext: "webp"),
        ":mop:": Info(file: "mop", ext: "webp"),
        ":paintbrush:": Info(file: "paintbrush", ext: "webp"),
        ":poison:": Info(file: "poison", ext: "webp"),
        ":suit:": Info(file: "suit", ext: "webp"),
        ":tomb:": Info(file: "tomb", ext: "webp"),
        ":tree:": Info(file: "tree", ext: "webp"),
        ":trap:": Info(file: "trap", ext: "webp"),
        ":turkey:": Info(file: "turkey", ext: "webp"),
        ":bee:": Info(file: "bee", ext: "webp"),
        ":charger:": Info(file: "charger", ext: "webp"),
        ":cloth:": Info(file: "cloth", ext: "webp"),
        ":drill:": Info(file: "drill", ext: "webp"),
        ":drill2:": Info(file: "drill2", ext: "webp"),
        ":hat:": Info(file: "hat", ext: "webp"),
        ":lobster:": Info(file: "lobster", ext: "webp"),
        ":loot:": Info(file: "loot", ext: "webp"),
        ":medalsilver:": Info(file: "medalsilver", ext: "webp"),
        ":rose2:": Info(file: "rose2", ext: "webp"),
        ":saw:": Info(file: "saw", ext: "webp"),
        ":scream:": Info(file: "scream", ext: "webp"),
        ":shirt:": Info(file: "shirt", ext: "webp"),
        ":shirt2:": Info(file: "shirt2", ext: "webp"),
        ":violin:": Info(file: "violin", ext: "webp"),
        ":dice1:": Info(file: "dice1", ext: "webp"),
        ":dice2:": Info(file: "dice2", ext: "webp"),
        ":dice3:": Info(file: "dice3", ext: "webp"),
        ":dice4:": Info(file: "dice4", ext: "webp"),
        ":dice5:": Info(file: "dice5", ext: "webp"),
        ":dice6:": Info(file: "dice6", ext: "webp"),
        ":lore:": Info(file: "lore", ext: "webp"),
    ]

    static func info(for token: String) -> Info? {
        let k = token.lowercased()
        if let hit = all[k] { return hit }
        if !k.hasPrefix(":"), let hit = all[":\(k):"] { return hit }
        return nil
    }

    static func siteURL(file: String, ext: String = "webp") -> URL? {
        URL(string: "https://raw.githubusercontent.com/UltiMafia/Ultimafia/master/react_main/src/images/emotes/\(file).\(ext)")
    }

    static func customURL(_ path: String) -> URL? {
        let s = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return URL(string: s) }
        if s.hasPrefix("/") { return URL(string: "\(UMConfig.site)" + s) }
        return URL(string: "\(UMConfig.site)/" + s)
    }
}


enum UMInlinePart {
    case text(String)
    case emote(UMEmotes.Info)
}

func umEmoteParts(_ raw: String) -> [UMInlinePart] {
    let tokens = raw.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    var out: [UMInlinePart] = []
    var textBuf = ""
    func flushText() {
        if !textBuf.isEmpty {
            out.append(.text(textBuf))
            textBuf = ""
        }
    }
    for tok in tokens {
        if let info = UMEmotes.info(for: tok) {
            flushText()
            out.append(.emote(info))
        } else {
            if !textBuf.isEmpty { textBuf += " " }
            textBuf += tok
        }
    }
    flushText()
    return out.isEmpty ? [.text(raw)] : out
}

struct UMEmoteView: View {
    var token: String
    var kind: String = ""
    var path: String = ""
    var size: CGFloat = 22

    var body: some View {
        if let url = resolvedURL {
            AnimatedWebPView(url: url, showsPlaceholder: false, fitHeight: size)
                .fixedSize()
        } else {
            Text(token)
        }
    }

    private var resolvedURL: URL? {
        let k = kind.lowercased()
        if k == "custom" || k == "sticker" {
            return UMEmotes.customURL(path)
        }
        if let info = UMEmotes.info(for: token) {
            return info.url
        }
        if !path.isEmpty {
            return UMEmotes.customURL(path)
        }
        return nil
    }
}

struct UMFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxW = proposal.width ?? 10_000
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var width: CGFloat = 0
        var origins: [CGPoint] = []
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxW {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            width = max(width, x - spacing)
            rowH = max(rowH, size.height)
        }
        return (CGSize(width: min(maxW, max(width, 0)), height: y + rowH), origins)
    }
}

/// Site-exact emote splitting for markdown: a word is an emote only when it equals a site emote
/// key (case-insensitive), e.g. `:gun:`. Plain words like "gun" stay text, as on the website.
/// Spacing is preserved exactly.
func umStrictEmoteParts(_ raw: String) -> [UMInlinePart] {
    var out: [UMInlinePart] = []
    var textBuf = ""
    for (idx, tok) in raw.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
        if idx > 0 { textBuf += " " }
        if let info = UMEmotes.all[tok.lowercased()] {
            if !textBuf.isEmpty { out.append(.text(textBuf)); textBuf = "" }
            out.append(.emote(info))
        } else {
            textBuf += tok
        }
    }
    if !textBuf.isEmpty { out.append(.text(textBuf)) }
    return out
}

/// `#RGB`, `#RRGGBB` or `#RRGGBBAA`, the only forms the site's {color:} accepts.
func umHexColor(_ s: String) -> Color? {
    guard s.hasPrefix("#") else { return nil }
    var hex = String(s.dropFirst())
    guard [3, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
    if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
    if hex.count == 6 { hex += "FF" }
    guard let v = UInt64(hex, radix: 16) else { return nil }
    return Color(.sRGB,
                 red: Double((v >> 24) & 0xFF) / 255,
                 green: Double((v >> 16) & 0xFF) / 255,
                 blue: Double((v >> 8) & 0xFF) / 255,
                 opacity: Double(v & 0xFF) / 255)
}

/// Emote bitmaps sized for inline `Text(Image)`, so emotes flow and wrap with the text.
/// Height is fixed; width follows the image's own aspect ratio. Until the download lands a
/// square transparent placeholder is returned, and the view re-lays out once the image arrives.
@MainActor @Observable
final class UMInlineEmoteCache {
    static let shared = UMInlineEmoteCache()
    static let side: CGFloat = 20

    private(set) var images: [URL: UIImage] = [:]
    @ObservationIgnored private var inflight: Set<URL> = []
    @ObservationIgnored private lazy var blank: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: Self.side, height: Self.side)).image { _ in }
    }()

    func image(for url: URL) -> UIImage {
        if let hit = images[url] { return hit }
        if !inflight.contains(url) {
            inflight.insert(url)
            Task { await load(url) }
        }
        return blank
    }

    private func load(_ url: URL) async {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = UIImage(data: data) else { return }
        let side = Self.side
        let w = max(source.size.width, 1), h = max(source.size.height, 1)
        let size = CGSize(width: (side * w / h).rounded(.up), height: side)
        images[url] = UIGraphicsImageRenderer(size: size).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
