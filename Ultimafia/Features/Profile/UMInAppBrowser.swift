import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

struct UMBrowserItem: Identifiable, Hashable {
    var url: URL
    var id: String { url.absoluteString }
}

struct UMInAppBrowser: View {
    let url: URL
    var onClose: () -> Void

    @State private var title = ""
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? (url.host ?? "Link") : title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(url.host ?? url.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(UMTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(UMTheme.elevated, in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(UMTheme.card)

            ZStack(alignment: .top) {
                if loading {
                    ProgressView()
                        .tint(UMTheme.blood)
                        .padding(.top, 8)
                        .zIndex(1)
                }
                #if canImport(WebKit)
                UMBrowserWebView(url: url, title: $title, loading: $loading)
                #else
                VStack(spacing: 12) {
                    Text("Can't open this page in-app.")
                        .foregroundStyle(UMTheme.muted)
                    Link("Open in Safari", destination: url)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            }
        }
        .background(UMTheme.bg.ignoresSafeArea())
    }
}

#if canImport(WebKit)
private struct UMBrowserWebView: UIViewRepresentable {
    let url: URL
    @Binding var title: String
    @Binding var loading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(title: $title, loading: $loading)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.backgroundColor = .black
        web.isOpaque = false
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        var title: Binding<String>
        var loading: Binding<Bool>

        init(title: Binding<String>, loading: Binding<Bool>) {
            self.title = title
            self.loading = loading
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            loading.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loading.wrappedValue = false
            if let t = webView.title, !t.isEmpty {
                title.wrappedValue = t
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            loading.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            loading.wrappedValue = false
        }
    }
}
#endif
