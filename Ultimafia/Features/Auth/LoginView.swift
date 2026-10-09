import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var email = RememberedLogin.email
    @State private var password = RememberedLogin.isEnabled ? (RememberedLogin.password ?? "") : ""
    @State private var rememberMe = RememberedLogin.isEnabled
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "theatermasks.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(UMTheme.blood)
                Text("ULTIMAFIA")
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .tracking(2)
                Text("Play chat mafia on your phone.")
                    .font(.subheadline)
                    .foregroundStyle(UMTheme.muted)
            }
            .padding(.bottom, 36)

            VStack(spacing: 12) {
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

                Toggle(isOn: $rememberMe) {
                    Text("Remember me")
                        .foregroundStyle(.white)
                }
                .tint(UMTheme.blood)

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
                            Text(creating ? "Create account" : "Sign in")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .background(UMTheme.blood, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .disabled(app.isBusy || email.isEmpty || password.count < 6)

                Button(creating ? "Have an account? Sign in" : "New here? Create an account") {
                    creating.toggle()
                    app.errorMessage = nil
                }
                .font(.footnote)
                .foregroundStyle(UMTheme.muted)
            }
            .padding(.horizontal, 24)

            Spacer()
            Text("Talks to ultimafia.com. Same account as the website.")
                .font(.caption2)
                .foregroundStyle(UMTheme.muted)
                .padding(.bottom, 24)
        }
        .background(UMTheme.bg.ignoresSafeArea())
        .onChange(of: rememberMe) { _, on in
            if !on { RememberedLogin.clear() }
        }
    }
}
