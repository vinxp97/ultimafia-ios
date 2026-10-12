import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var app
    // Legacy "Remember me" values prefill once; they're cleared after the next sign-in.
    @State private var email = RememberedLogin.email
    @State private var password = RememberedLogin.isEnabled ? (RememberedLogin.password ?? "") : ""
    @FocusState private var passwordFocused: Bool
    @State private var creating = false
    @State private var confirm = ""
    @State private var birthday = ""

    /// Parses MM/DD/YYYY; nil if incomplete or not a real date.
    private var birthDate: Date? {
        let parts = birthday.split(separator: "/").compactMap { Int($0) }
        guard birthday.count == 10, parts.count == 3, parts[2] > 1900 else { return nil }
        var c = DateComponents(); c.month = parts[0]; c.day = parts[1]; c.year = parts[2]
        let cal = Calendar(identifier: .gregorian)
        guard let d = cal.date(from: c), cal.component(.month, from: d) == parts[0],
              cal.component(.day, from: d) == parts[1], d <= Date() else { return nil }
        return d
    }

    private var isUnder13: Bool {
        guard let d = birthDate else { return false }
        let age = Calendar(identifier: .gregorian).dateComponents([.year], from: d, to: Date()).year ?? 0
        return age < 13
    }

    private func formatBirthday(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(8))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i == 2 || i == 4 { out.append("/") }
            out.append(ch)
        }
        return out
    }

    private var canSubmit: Bool {
        !app.isBusy && !email.isEmpty && password.count >= 6 && (!creating || (password == confirm && birthDate != nil && !isUnder13))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 108 * 0.2237, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                    .accessibilityLabel("Ultimafia")
                Text("ULTIMAFIA")
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .tracking(2)
                Text("Play chat mafia on your phone.")
                    .font(.subheadline)
                    .foregroundStyle(UMTheme.muted)
            }
            .padding(.bottom, 36)

            VStack(spacing: 12) {
                Picker("Mode", selection: $creating) {
                    Text("Log in").tag(false)
                    Text("Register").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                TextField("Email", text: $email)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                    .padding(14)
                    .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 12))
                SecureField("Password", text: $password)
                    .focused($passwordFocused)
                    .textContentType(creating ? .newPassword : .password)
                    .padding(14)
                    .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 12))

                if creating {
                    SecureField("Confirm password", text: $confirm)
                        .textContentType(.newPassword)
                        .padding(14)
                        .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    TextField("Birthday (MM/DD/YYYY)", text: $birthday)
                        .textContentType(.birthdate)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .padding(14)
                        .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: birthday) { _, v in
                            let f = formatBirthday(v)
                            if f != v { birthday = f }
                        }
                    if isUnder13 {
                        Text("Ultimafia is for 13+ users only.")
                            .font(.footnote)
                            .foregroundStyle(UMTheme.mafia)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if birthday.count == 10 && birthDate == nil {
                        Text("Enter a real date as MM/DD/YYYY.")
                            .font(.footnote)
                            .foregroundStyle(UMTheme.mafia)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !confirm.isEmpty && confirm != password {
                        Text("Passwords don't match.")
                            .font(.footnote)
                            .foregroundStyle(UMTheme.mafia)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let error = app.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(UMTheme.mafia)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        if creating {
                            await app.signUp(email: email, password: password)
                        } else {
                            await app.signIn(email: email, password: password)
                        }
                    }
                } label: {
                    Group {
                        if app.isBusy {
                            ProgressView().tint(.white)
                        } else {
                            Text(creating ? "Register" : "Log in")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(UMPrimaryButtonStyle())
                .disabled(!canSubmit)

            }
            .padding(.horizontal, 24)

            Spacer()
            SavedAccountsRow()
            Text("Talks to ultimafia.com. Same account as the website.")
                .font(.caption2)
                .foregroundStyle(UMTheme.muted)
                .padding(.bottom, 24)
        }
        .background(UMTheme.bg.ignoresSafeArea())
        .animation(.default, value: creating)
        .onChange(of: creating) { _, _ in
            app.errorMessage = nil
            confirm = ""
            birthday = ""
        }
        .onAppear { applyPrefill(app.loginPrefillEmail) }
        .onChange(of: app.loginPrefillEmail) { _, v in applyPrefill(v) }
    }
}


extension LoginView {
    fileprivate func applyPrefill(_ value: String?) {
        guard let value else { return }
        creating = false
        email = value
        password = ""
        if !value.isEmpty { passwordFocused = true }
    }
}

/// Saved accounts, newest first. Tap to switch; long-press to remove from this device.
struct SavedAccountsRow: View {
    @Environment(AppModel.self) private var app
    private var store: AccountStore { .shared }

    var body: some View {
        let accounts = store.sorted
        if !accounts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved accounts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(UMTheme.muted)
                    .padding(.horizontal, 24)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(accounts) { account in
                            Button {
                                Task { await app.switchToAccount(account) }
                            } label: {
                                VStack(spacing: 6) {
                                    UMAvatarView(player: account.player, size: 56)
                                    PlayerNameView(player: account.player, fontSize: 13)
                                        .lineLimit(1)
                                        .frame(maxWidth: 84)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(app.isBusy)
                            .contextMenu {
                                Button("Remove from This Device", systemImage: "trash", role: .destructive) {
                                    app.removeSavedAccount(account.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 4)
                }
            }
            .padding(.bottom, 12)
        }
    }
}

/// Full-width filled button: the whole rounded shape is the hit target, with pressed/disabled states.
struct UMPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(UMTheme.blood, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
