import SwiftUI

/// Turns API/network failures into short user-facing text. Never shows raw response bodies
/// (e.g. an nginx 502 HTML page during an outage).
nonisolated enum UMFriendlyError {
    /// Text for a failed HTTP response. Short plain-text server messages (e.g. "You can't join
    /// this game.") are kept; HTML, long bodies and 5xx errors become a generic message.
    static func serverText(data: Data, status: Int, fallback: String) -> String {
        if status >= 500 { return "Ultimafia's server is having trouble (\(status)). Try again in a moment." }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty || looksLikeMarkup(text) || text.count > 200 || text.contains("\n") {
            return fallback
        }
        return text
    }

    static func looksLikeMarkup(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.hasPrefix("<") || t.contains("<html") || t.contains("<!doctype") || t.contains("</")
    }

    /// Text for any thrown error.
    static func message(for error: Error) -> String {
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "You're offline. Check your connection."
            case .timedOut:
                return "Ultimafia took too long to respond."
            default:
                return "Couldn't reach Ultimafia."
            }
        }
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if looksLikeMarkup(text) || text.count > 200 { return "Something went wrong. Try again in a moment." }
        return text
    }
}

/// "Couldn't load X." + reason + Tap to retry, for list screens.
struct UMLoadErrorView: View {
    let title: String
    var detail: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(UMTheme.muted)
            Text(title).font(.subheadline.weight(.semibold))
            if let detail, !detail.isEmpty {
                Text(detail).font(.footnote).foregroundStyle(UMTheme.muted)
                    .multilineTextAlignment(.center)
            }
            Button("Tap to retry", action: retry)
                .buttonStyle(.bordered)
                .tint(UMTheme.blood)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24).padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: retry)
    }
}
