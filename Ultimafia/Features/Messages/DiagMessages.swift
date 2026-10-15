#if DEBUG
import SwiftUI

/// DEBUG: `-UMDiagMessages public|dms|thread|new|settings` shows the Messages screens with sample
/// data (no sign-in, no network) for screenshots.
struct DiagMessagesView: View {
    var screen: String
    @Environment(AppModel.self) private var app

    init(screen: String) {
        self.screen = screen
        UMChatStore.shared.loadDemo(selfId: "me")
    }

    var body: some View {
        Group {
            switch screen {
            case "dms": MessagesView(mode: .direct)
            case "thread": NavigationStack { DMThreadView(store: .shared, channelId: "d1") }
            case "new": NewMessageView(store: .shared)
            case "settings": NavigationStack { List { DMNotificationSettingsSection() }.scrollContentBackground(.hidden).background(UMTheme.bg) }
            default: MessagesView(mode: .publicChat)
            }
        }
    }
}
#endif
