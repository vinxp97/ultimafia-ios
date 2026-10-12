import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("um.chatLayout") private var chatLayout: ChatLayout = .standard
    @AppStorage("um.showTypingIndicator") private var showTypingIndicator = true
    @AppStorage("um.showNameAutofill") private var showTabButton = true
    @AppStorage("um.showEmoteAutocomplete") private var showEmoteAutocomplete = true
    @AppStorage("um.showSetupGuides") private var showSetupGuides = true
    @AppStorage("um.showVotingLog") private var showVotingLog = true
    @AppStorage("um.musicVolume") private var musicVolume = 1.0
    @AppStorage("um.sfxVolume") private var sfxVolume = 1.0
    @AppStorage("um.deathSoundVolume") private var deathSoundVolume = 1.0
    @AppStorage(GameAudio.pregameMusicKey) private var pregameMusicVolume = 1.0
    @AppStorage(GameAudio.alertKey) private var alertVolume = 1.0
    @State private var confirmMuteAlerts = false
    @State private var confirmClearCache = false
    @State private var cacheBytes: Int64 = 0
    @State private var clearedMessage: String?
    @State private var trophies: [UMTrophy] = []
    @State private var selectedTrophy: UMTrophy?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let me = app.user?.cosmeticPlayer
                    HStack(spacing: 14) {
                        if let me {
                            UMAvatarView(player: me, size: 52)
                            PlayerNameView(player: me, fontSize: 20)
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(UMTheme.card)
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
                    Toggle("Show Autofill Name", isOn: $showTabButton)
                        .listRowBackground(UMTheme.card)
                    Toggle("Show Autofill Emoji", isOn: $showEmoteAutocomplete)
                        .listRowBackground(UMTheme.card)
                    Toggle("Show Voting Log", isOn: $showVotingLog)
                        .listRowBackground(UMTheme.card)
                    Toggle("Show Setup Guides", isOn: $showSetupGuides)
                        .listRowBackground(UMTheme.card)
                }
                if !trophies.isEmpty {
                    Section("Trophies") {
                        ForEach(trophies) { t in
                            Button { selectedTrophy = t } label: {
                                HStack(spacing: 12) {
                                    UMTrophyIcon(trophy: t, size: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.name).foregroundStyle(.white)
                                        Text(t.awardedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Date unknown")
                                            .font(.caption)
                                            .foregroundStyle(UMTheme.muted)
                                    }
                                }
                            }
                            .listRowBackground(UMTheme.card)
                        }
                    }
                }
                Section {
                    NavigationLink("Custom Emojis & Stickers") { CustomMediaOrderView() }
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
                    volumeRow("Pregame Music Volume", $pregameMusicVolume) {
                        GameMusic.applyVolume()
                    }
                    volumeRow("Alert Volume", $alertVolume) {
                        if alertVolume == 0 { confirmMuteAlerts = true }
                        GameSFX.applyVolume()
                        ReadyBell.applyVolume()
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
                    Button("Clear Custom Asset Cache", role: .destructive) { confirmClearCache = true }
                        .listRowBackground(UMTheme.card)
                } header: {
                    Text("Storage")
                } footer: {
                    Text(clearedMessage ?? "Custom emotes, stickers and avatars saved on this device: \(Self.mb(cacheBytes)).")
                }
                Section {
                    HStack {
                        Text("Device")
                        Spacer()
                        Text(String(DeviceIdentity.installId.prefix(8)) + "…")
                            .foregroundStyle(UMTheme.muted)
                            .monospaced()
                            .textSelection(.enabled)
                    }
                    .listRowBackground(UMTheme.card)
                } footer: {
                    Text("Install ID, stored only on this device.")
                }
                Section {
                    if app.seatedGameId == nil {
                        Button("Add Another Account") { app.addAnotherAccount() }
                            .listRowBackground(UMTheme.card)
                    }
                    Button("Sign out", role: .destructive) {
                        Task { await app.signOut() }
                    }
                    .listRowBackground(UMTheme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(UMTheme.bg.ignoresSafeArea())
            .navigationTitle("You")
            // Web asks before silencing alerts; declining leaves them at 10%.
            .task { cacheBytes = UMCustomAssetCache.diskBytes() }
            .task(id: app.user?.id) { await loadTrophies() }
            .sheet(item: $selectedTrophy) { UMTrophyDetailSheet(trophy: $0) }
            .confirmationDialog("Clear custom asset cache?", isPresented: $confirmClearCache, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    Task {
                        let freed = await UMCustomAssetCache.shared.clear()
                        UMImageCache.shared.evictCustomUserAssets()
                        cacheBytes = 0
                        clearedMessage = "Cleared \(Self.mb(freed)) of custom emotes, stickers and avatars."
                    }
                }
            } message: {
                Text("Removes saved custom emotes, stickers and avatars. They'll download again when needed. Role icons, fonts, sounds and site emotes are kept, and saved accounts, sign-ins and settings aren't affected.")
            }
            .alert("Disable alert sounds?", isPresented: $confirmMuteAlerts) {
                Button("Disable", role: .destructive) {}
                Button("Keep at 10%", role: .cancel) { alertVolume = 0.1 }
            } message: {
                Text("You won't be alerted when a game starts or when you're about to be kicked for inactivity.")
            }
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

    private static func mb(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(UMTheme.muted)
        }
        .listRowBackground(UMTheme.card)
    }

    private func loadTrophies() async {
        guard let id = app.user?.id, !id.isEmpty,
              let blob = try? await APIClient.shared.userProfile(id) else { return }
        trophies = UMTrophy.list(from: blob)
    }

}
