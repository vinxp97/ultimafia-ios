import SwiftUI

struct SetupSearchView: View {
    @Environment(AppModel.self) private var app
    @State private var filter: SetupFilter = .popular
    @State private var query = ""
    @State private var setups: [SetupInfo] = []
    @State private var page = 1
    @State private var pages = 1
    @State private var loading = false
    @State private var error: String?
    @State private var hosting: SetupInfo?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                filterChips
                searchField
                if let error {
                    Text(error).font(.footnote).foregroundStyle(UMTheme.mafia)
                }
                ForEach(setups) { setup in
                    SetupSearchCard(setup: setup) { hosting = setup }
                }
                if loading {
                    ProgressView().tint(UMTheme.blood).frame(maxWidth: .infinity).padding()
                } else if setups.isEmpty, error == nil {
                    Text("No setups found.").foregroundStyle(UMTheme.muted).frame(maxWidth: .infinity).padding()
                } else if page < pages {
                    Button("Load more") { Task { await load(reset: false) } }
                        .frame(maxWidth: .infinity)
                        .tint(UMTheme.blood)
                }
            }
            .padding(16)
        }
        .background(UMTheme.bg.ignoresSafeArea())
        .navigationTitle("Host a Game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { app.suppressAppBar = true }
        .onDisappear { app.suppressAppBar = false }
        .task(id: filter) { await load(reset: true) }
        .task(id: query) {
            // Debounce typing; .task(id:) cancels the previous run.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
        .sheet(item: $hosting) { setup in
            HostGameView(setup: setup)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SetupFilter.allCases) { f in
                    let selected = f == filter
                    Button { filter = f } label: {
                        Text(f.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selected ? UMTheme.elevated : UMTheme.card, in: Capsule())
                            .overlay(Capsule().stroke(selected ? UMTheme.blood : UMTheme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(UMTheme.muted)
            TextField("Search setups or roles", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(UMTheme.muted) }
                    .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private func load(reset: Bool) async {
        let next = reset ? 1 : page + 1
        loading = true
        defer { loading = false }
        do {
            let result = try await APIClient.shared.searchSetups(filter: filter, query: query, page: next)
            guard !Task.isCancelled else { return }
            if reset { setups = result.setups } else {
                let known = Set(setups.map(\.id))
                setups += result.setups.filter { !known.contains($0.id) }
            }
            page = next
            pages = max(1, result.pages)
            error = nil
        } catch is CancellationError {
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            self.error = error.localizedDescription
        }
    }
}

struct SetupSearchCard: View {
    let setup: SetupInfo
    var onHost: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onHost) {
                Text("Host")
                    .font(.subheadline.weight(.bold))
                    .frame(minWidth: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(UMTheme.blood)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(setup.clippedName).font(.headline).lineLimit(1)
                    if setup.ranked == true { tag("Ranked", UMTheme.mafia) }
                    if setup.competitive == true { tag("Comp", .yellow) }
                    Spacer(minLength: 0)
                    Label("\(setup.total?.value ?? 0)", systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(UMTheme.muted)
                }
                // Reuses the lobby strip: all roles, tappable descriptions, and the
                // cycle button for multi-roleset setups.
                LobbySetupStrip(setup: setup, gameType: setup.gameType ?? "Mafia")
                if let creator = setup.creator?.name {
                    Text("by \(creator)").font(.caption).foregroundStyle(UMTheme.muted)
                }
            }
        }
        .padding(12)
        .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}
