import SwiftUI

/// You tab: the user's own custom emotes and stickers, drag-to-reorder. The order drives the
/// colon autocomplete row and is saved per user (device + iCloud key-value store).
struct CustomMediaOrderView: View {
    @Environment(AppModel.self) private var app
    @State private var emotes: [Item] = []
    @State private var stickers: [Item] = []
    @State private var loaded = false

    struct Item: Identifiable, Hashable {
        let code: String
        let url: URL
        let sticker: Bool
        var id: String { EmoteOrderStore.key(code: code, sticker: sticker) }
    }

    var body: some View {
        List {
            if loaded && emotes.isEmpty && stickers.isEmpty {
                Text("You don't have any custom emojis or stickers yet.")
                    .foregroundStyle(UMTheme.muted)
                    .listRowBackground(UMTheme.card)
            }
            if !emotes.isEmpty {
                Section {
                    ForEach(emotes) { row($0) }
                        .onMove { emotes.move(fromOffsets: $0, toOffset: $1); save() }
                } header: {
                    Text("Emojis")
                } footer: {
                    triggerHint(":", "emoji")
                }
            }
            if !stickers.isEmpty {
                Section {
                    ForEach(stickers) { row($0) }
                        .onMove { stickers.move(fromOffsets: $0, toOffset: $1); save() }
                } header: {
                    Text("Stickers")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        triggerHint(";", "sticker")
                        Text("Tap Edit and drag to choose what shows first in the picker.")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(UMTheme.bg.ignoresSafeArea())
        .navigationTitle("Emojis & Stickers")
        .toolbar { EditButton() }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: EmoteOrderStore.didChange)) { _ in rebuild() }
    }

    /// "Type : in chat to pick an emoji (e.g. :name:)." with the trigger characters in monospaced.
    private func triggerHint(_ c: String, _ noun: String) -> Text {
        let mono = Font.footnote.monospaced().weight(.semibold)
        let key = Text(c).font(mono).foregroundStyle(Color.primary)
        let example = Text("\(c)name\(c)").font(mono).foregroundStyle(Color.primary)
        return Text("Type \(key) in chat to pick \(noun == "emoji" ? "an" : "a") \(noun) (e.g. \(example)).")
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 12) {
            AnimatedWebPView(url: item.url, showsPlaceholder: false, fitHeight: item.sticker ? 48 : 28)
                .fixedSize()
                .frame(minWidth: 48, alignment: .center)
            Text(item.code)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer()
            if item.sticker {
                Text("STICKER")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(UMTheme.blood)
            }
        }
        .listRowBackground(UMTheme.card)
    }

    private func load() async {
        if app.myCustomEmotes.isEmpty && app.myCustomStickers.isEmpty {
            await app.loadMyCustomMedia()
        }
        rebuild()
        loaded = true
    }

    private func rebuild() {
        let rank = EmoteOrderStore.shared.rank(for: app.user?.id)
        func items(_ map: [String: String], sticker: Bool) -> [Item] {
            map.compactMap { code, path in UMMediaURL.resolve(path).map { Item(code: code, url: $0, sticker: sticker) } }
                .sorted { a, b in
                    let ia = rank[a.id] ?? Int.max, ib = rank[b.id] ?? Int.max
                    return ia != ib ? ia < ib : a.code < b.code
                }
        }
        emotes = items(app.myCustomEmotes, sticker: false)
        stickers = items(app.myCustomStickers, sticker: true)
    }

    private func save() {
        EmoteOrderStore.shared.setOrder(emotes.map(\.id) + stickers.map(\.id), for: app.user?.id)
    }
}
