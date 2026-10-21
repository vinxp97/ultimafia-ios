import SwiftUI

/// Hidden diagnostics log (long-press the © line at the bottom of the You page).
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = "Loading…"
    @State private var exportURL: URL?
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            .navigationTitle("Diagnostics")
            .umInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Reload")
                    if let exportURL {
                        ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Share log")
                    }
                    Button(role: .destructive) { confirmClear = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Clear log")
                }
            }
            .confirmationDialog("Clear the diagnostics log?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Log", role: .destructive) {
                    UMDiag.clear { Task { @MainActor in reload() } }
                }
            }
            .task { reload() }
        }
    }

    private func reload() {
        UMDiag.readAll { all in
            // Show the newest ~300 KB; the shared file has everything.
            let tail = all.count > 300_000 ? "…\n" + String(all.suffix(300_000)) : all
            Task { @MainActor in text = tail.isEmpty ? "(empty)" : tail }
        }
        UMDiag.exportFile { url in Task { @MainActor in exportURL = url } }
    }
}
