import SwiftUI

@main
struct UltimafiaApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .tint(UMTheme.blood)
                .task { UMNameFonts.shared.loadIfNeeded() }
        }
    }
}
