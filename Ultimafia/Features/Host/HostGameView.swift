import SwiftUI

struct HostGameView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let setup: SetupInfo
    @State private var o = HostOptions()
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        umBody.umKeyboardDismissBar()
    }

    @ViewBuilder private var umBody: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(setup.displayName).font(.headline)
                        Text("\(setup.total?.value ?? 0) players").font(.caption).foregroundStyle(UMTheme.muted)
                        LobbySetupStrip(setup: setup, gameType: setup.gameType ?? "Mafia")
                    }
                    .listRowBackground(UMTheme.card)
                }
                Section {
                    TextField("Lobby Name", text: $o.lobbyName)
                    Picker("Lobby", selection: $o.lobby) {
                        ForEach(HostOptions.lobbies, id: \.self) { Text($0).tag($0) }
                    }
                    if o.showPrivateAndGuests {
                        Toggle("Private", isOn: $o.isPrivate)
                        Toggle("Allow Guests", isOn: $o.guests)
                    }
                    Toggle("Spectating", isOn: $o.spectating)
                    Toggle("Ready Check", isOn: $o.readyCheck)
                    Toggle("Anonymous Game", isOn: $o.anonymousGame)
                    if o.anonymousGame {
                        LabeledContent("Deck ID") {
                            TextField("Deck ID", text: $o.anonymousDeckId)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    if o.showRanked { Toggle("Ranked", isOn: $o.ranked) }
                    if o.showCompetitive { Toggle("Competitive", isOn: $o.competitive) }
                    if o.showAdvanced { Toggle("Advanced Hosting", isOn: $o.advancedHosting) }
                    if o.showNoVeg { Toggle("No Vegging", isOn: $o.noVeg) }
                    if o.showDuration {
                        Toggle("Configure Duration", isOn: $o.configureDuration)
                        if o.configureDuration {
                            Stepper("Day Length: \(o.dayLength) min", value: $o.dayLength, in: 1...30)
                            Stepper("Night Length: \(o.nightLength) min", value: $o.nightLength, in: 1...10)
                            Stepper("Pregame Wait: \(o.pregameWaitLength) hr", value: $o.pregameWaitLength, in: 1...6)
                            Stepper("Extension Length: \(o.extendLength) min", value: $o.extendLength, in: 0...5)
                        }
                    }
                }
                .listRowBackground(UMTheme.card)
                .tint(UMTheme.blood)

                if let error {
                    Section { Text(error).foregroundStyle(UMTheme.mafia) }
                        .listRowBackground(UMTheme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(UMTheme.bg.ignoresSafeArea())
            .animation(.default, value: o)
            .navigationTitle("Host Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting { ProgressView() } else {
                        Button("Host") { Task { await host() } }.bold()
                    }
                }
            }
            .onChange(of: o.competitive) { _, on in if on { o.lobby = "Competitive" } }
        }
        .preferredColorScheme(.dark)
    }

    private func host() async {
        submitting = true
        defer { submitting = false }
        do {
            let id = try await APIClient.shared.hostGame(o, setupId: setup.id)
            dismiss()
            app.resumeGame(id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
