import SwiftUI
#if targetEnvironment(macCatalyst)
import UIKit

/// Mac (Catalyst, "Optimize for Mac") window chrome and menu bar. iPhone/iPad never compile this.
enum UMMac {
    static let minimumSize = CGSize(width: 1100, height: 720)
    static let preferredSize = CGSize(width: 1440, height: 900)

    /// Minimum size, a desktop-sized first window, and a unified title bar without a title.
    @MainActor
    static func configure(_ scene: UIWindowScene) {
        scene.sizeRestrictions?.minimumSize = minimumSize
        if let titlebar = scene.titlebar {
            titlebar.titleVisibility = .hidden
            titlebar.toolbarStyle = .unified
        }
        let frame = scene.effectiveGeometry.systemFrame
        if frame.width < preferredSize.width - 1 {
            let prefs = UIWindowScene.GeometryPreferences.Mac(
                systemFrame: CGRect(origin: frame.origin, size: preferredSize))
            scene.requestGeometryUpdate(prefs) { _ in }
        }
        #if DEBUG
        scheduleSnapshot(scene)
        #endif
    }

    #if DEBUG
    /// `-UMMacSnapshot <path.png> [seconds]`: write the window's contents to a PNG (screenshots
    /// without Screen Recording permission). DEBUG only.
    @MainActor
    private static func scheduleSnapshot(_ scene: UIWindowScene) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-UMMacSnapshot"), args.indices.contains(i + 1) else { return }
        let path = args[i + 1]
        let delay = args.indices.contains(i + 2) ? Double(args[i + 2]) ?? 8 : 8
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else { return }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try? image.pngData()?.write(to: URL(fileURLWithPath: path))
            UMDiag.log("mac", "snapshot \(path)")
        }
    }
    #endif
}

/// Finds the hosting window scene once it exists and applies `UMMac.configure`.
struct UMMacWindowConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}

    final class Probe: UIView {
        private var done = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard !done, let scene = window?.windowScene else { return }
            done = true
            UMMac.configure(scene)
        }
    }
}

/// Menu bar: no "New Window" (one game connection per app), and View > section shortcuts.
struct UMMacCommands: Commands {
    var app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Go") {
            ForEach(Array(UMAppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { app.select(section) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(section == .messages && (app.game != nil || app.seatedGameId != nil))
            }
        }
    }
}
#endif
