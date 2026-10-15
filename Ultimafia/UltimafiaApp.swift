import SwiftUI

@main
struct UltimafiaApp: App {
    @State private var appModel = AppModel()
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(UMAppDelegate.self) private var appDelegate
    #endif

    init() {
        UMDiag.log("app", "launch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
        UMDiag.startWatchdog()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .tint(UMTheme.blood)
                .task { UMNameFonts.shared.loadIfNeeded() }
        }
    }
}
