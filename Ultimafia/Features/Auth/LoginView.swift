import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var email = RememberedLogin.email
    @State private var password = RememberedLogin.isEnabled ? (RememberedLogin.password ?? "") : ""
    @State private var rememberMe = RememberedLogin.isEnabled
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
                } else {
                    Toggle(isOn: $rememberMe) {
                        Text("Remember me")
                            .foregroundStyle(.white)
                    }
                    .tint(UMTheme.blood)
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
                            await app.signIn(email: email, password: password, remember: rememberMe)
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
                .buttonStyle(.plain)
                .background(UMTheme.blood, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.6)

            }
            .padding(.horizontal, 24)

            Spacer()
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
        .onChange(of: rememberMe) { _, on in
            if !on { RememberedLogin.clear() }
        }
    }
}
