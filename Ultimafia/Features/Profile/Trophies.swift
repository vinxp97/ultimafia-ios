import SwiftUI

/// One entry of `trophies` in GET user/:id/profile (site sorts newest award first; revoked ones are excluded server-side).
struct UMTrophy: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let ownerName: String?
    let awardedAt: Date?

    static func list(from blob: [String: Any]) -> [UMTrophy] {
        guard let raw = blob["trophies"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        let items: [UMTrophy] = raw.enumerated().map { index, t in
            var date: Date?
            if let s = t["createdAt"] as? String { date = iso.date(from: s) ?? isoPlain.date(from: s) }
            else if let n = t["createdAt"] as? Double { date = Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
            let name = (t["name"] as? String) ?? "Trophy"
            let type = ((t["type"] as? String) ?? "silver").lowercased()
            let owner = (t["owner"] as? [String: Any])?["name"] as? String
            return UMTrophy(id: (t["id"] as? String) ?? "\(index)-\(name)", name: name,
                            type: type, ownerName: owner, awardedAt: date)
        }
        // Server already returns -createdAt; re-sort defensively, keeping server order on ties/unknown dates.
        return items.enumerated().sorted { a, b in
            switch (a.element.awardedAt, b.element.awardedAt) {
            case let (x?, y?) where x != y: return x > y
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    var typeTitle: String { type.prefix(1).uppercased() + type.dropFirst() }

    var symbol: String { type == "crown" ? "crown.fill" : "trophy.fill" }

    var tint: Color {
        switch type {
        case "gold", "crown": return Color(red: 0.98, green: 0.78, blue: 0.2)
        case "bronze": return Color(red: 0.80, green: 0.50, blue: 0.24)
        default: return Color(red: 0.78, green: 0.80, blue: 0.84)
        }
    }

    var awardedText: String {
        awardedAt.map { $0.formatted(date: .long, time: .shortened) } ?? "Date unknown"
    }
}

struct UMTrophyIcon: View {
    let trophy: UMTrophy
    var size: CGFloat = 28
    var body: some View {
        Image(systemName: trophy.symbol)
            .font(.system(size: size * 0.62, weight: .semibold))
            .foregroundStyle(trophy.tint)
            .frame(width: size, height: size)
            .accessibilityLabel("\(trophy.name), \(trophy.typeTitle) trophy")
    }
}

struct UMTrophyDetailSheet: View {
    let trophy: UMTrophy
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        UMTrophyIcon(trophy: trophy, size: 56)
                        Text(trophy.name).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(UMTheme.card)
                }
                Section {
                    LabeledContent("Type", value: trophy.typeTitle).listRowBackground(UMTheme.card)
                    if let owner = trophy.ownerName {
                        LabeledContent("Owner", value: owner).listRowBackground(UMTheme.card)
                    }
                    LabeledContent("Awarded", value: trophy.awardedText).listRowBackground(UMTheme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(UMTheme.bg)
            .navigationTitle("Trophy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// Horizontal icon row for the top of a user profile. Renders nothing when empty.
struct UMTrophyRow: View {
    let trophies: [UMTrophy]
    @State private var selected: UMTrophy?
    var body: some View {
        if !trophies.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(trophies) { t in
                        Button { selected = t } label: { UMTrophyIcon(trophy: t, size: 34) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
            .sheet(item: $selected) { UMTrophyDetailSheet(trophy: $0) }
        }
    }
}
