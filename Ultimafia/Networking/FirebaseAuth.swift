import Foundation

enum FirebaseAuth {
    static func signIn(email: String, password: String) async throws -> String {
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "returnSecureToken": true,
        ]
        let result: FirebaseSignIn = try await post("signInWithPassword", body: body)
        if let msg = result.error?.message { throw UMError.message(firebaseMessage(msg)) }
        guard let token = result.idToken, !token.isEmpty else {
            throw UMError.message("Sign in failed.")
        }
        return token
    }

    static func signUp(email: String, password: String) async throws -> String {
        let domain = email.split(separator: "@").last.map(String.init)?.lowercased() ?? ""
        if !UMConfig.allowedEmailDomains.contains(domain) {
            throw UMError.message("That email domain is not allowed. Use a gmail/icloud/outlook address.")
        }
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "returnSecureToken": true,
        ]
        let result: FirebaseSignIn = try await post("signUp", body: body)
        if let msg = result.error?.message { throw UMError.message(firebaseMessage(msg)) }
        guard let token = result.idToken else { throw UMError.message("Could not create account.") }
        try await sendVerification(idToken: token)
        return token
    }

    static func sendVerification(idToken: String) async throws {
        let body: [String: Any] = [
            "requestType": "EMAIL_VERIFICATION",
            "idToken": idToken,
        ]
        struct Empty: Decodable {}
        let _: Empty = try await post("sendOobCode", body: body)
    }

    private static func post<T: Decodable>(_ method: String, body: [String: Any]) async throws -> T {
        var comps = URLComponents(string: "https://identitytoolkit.googleapis.com/v1/accounts:" + method)!
        comps.queryItems = [URLQueryItem(name: "key", value: UMConfig.firebaseAPIKey)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UMError.message("No response.") }
        if http.statusCode >= 400 {
            if let err = try? JSONDecoder().decode(FirebaseSignIn.self, from: data),
               let msg = err.error?.message {
                throw UMError.message(firebaseMessage(msg))
            }
            throw UMError.message("Auth failed (\(http.statusCode)).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func firebaseMessage(_ code: String) -> String {
        switch code {
        case "EMAIL_NOT_FOUND", "INVALID_LOGIN_CREDENTIALS", "INVALID_PASSWORD":
            return "Wrong email or password."
        case "EMAIL_EXISTS":
            return "An account with that email already exists."
        case "WEAK_PASSWORD":
            return "Password is too weak. Use at least 6 characters."
        case "TOO_MANY_ATTEMPTS_TRY_LATER":
            return "Too many attempts. Try again later."
        case "USER_DISABLED":
            return "This account is disabled."
        default:
            return code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
