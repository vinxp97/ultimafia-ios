import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("um.chatLayout") private var chatLayout: ChatLayout = .standard
    @AppStorage("um.showTypingIndicator") private var showTypingIndicator = true
    @AppStorage("um.showTabButton") private var showTabButton = true
    @AppStorage("um.showVotingLog") private var showVotingLog = true
    @AppStorage("um.musicVolume") private var musicVolume = 1.0
    @AppStorage("um.sfxVolume") private var sfxVolume = 1.0
    @AppStorage("um.deathSoundVolume") private var deathSoundVolume = 1.0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        UMAvatarView(
                            userId: app.user?.id,
                            hasAvatar: app.user?.avatar ?? false,
                            name: app.user?.name ?? "",
                            size: 52
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.user?.name ?? "Unknown")
                                .font(.title3.weight(.bold))
                            Text(app.user?.id ?? "")
                                .font(.caption.monospaced())
                                .foregroundStyle(UMTheme.muted)
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(UMTheme.card)
                }
                if app.seatedGameId != nil {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(app.seatedSetupName)
                                .font(.headline)
                            Text(app.seatedPhaseLabel)
                                .font(.subheadline)
                                .foregroundStyle(UMTheme.muted)
                            HStack {
                                Button("Return to Game") { app.resumeSeatedGame() }
                                Button("Leave", role: .destructive) { app.leaveActiveGame() }
                            }
                        }
                        .listRowBackground(UMTheme.card)
                    }
                }
                Section("Chat") {
                    Picker("Message layout", selection: $chatLayout) {
                        ForEach(ChatLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                    .pickerStyle(.menu)
                    .listRowBackground(UMTheme.card)
                    Toggle("Show Typing Indicator", isOn: $showTypingIndicator)
                        .listRowBackground(UMTheme.card)
                    Toggle("Show Tab button", isOn: $showTabButton)
                        .listRowBackground(UMTheme.card)
                    Toggle("Show Voting Log", isOn: $showVotingLog)
                        .listRowBackground(UMTheme.card)
                }
                Section("Audio") {
                    volumeRow("Music Volume", $musicVolume) {
                        GameMusic.applyVolume()
                        GameWinMusic.applyVolume()
                    }
                    volumeRow("Sound Volume", $sfxVolume) {
                        GameSFX.applyVolume()
                        ReadyBell.applyVolume()
                    }
                    volumeRow("Death Sound Volume", $deathSoundVolume) {
                        GameSFX.applyDeathVolume()
                    }
                }
                Section("Status") {
                    row("Coins", "\(app.user?.coins?.value ?? 0)")
                    row("Red hearts", "\(app.user?.redHearts?.value ?? 0)")
                    row("Gold hearts", "\(app.user?.goldHearts?.value ?? 0)")
                    if let game = app.user?.inGameId {
                        row("In game", game)
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await app.signOut() }
                    }
                    .listRowBackground(UMTheme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(UMTheme.bg.ignoresSafeArea())
            .navigationTitle("You")
        }
    }

    private func volumeRow(_ title: String, _ value: Binding<Double>, onChange: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .foregroundStyle(UMTheme.muted)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...1, step: 0.05)
                .tint(UMTheme.blood)
                .onChange(of: value.wrappedValue) { _, _ in onChange() }
        }
        .listRowBackground(UMTheme.card)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(UMTheme.muted)
        }
        .listRowBackground(UMTheme.card)
    }
}
