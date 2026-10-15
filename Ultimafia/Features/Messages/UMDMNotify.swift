import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Client-side DM notification options (You tab). Local notifications only; closed-app delivery
/// needs APNs (UMPush) once the server side exists.
enum UMDMNotify {
    static let enabledKey = "um.dm.notify"
    static let soundKey = "um.dm.sound"
    static let previewKey = "um.dm.preview"
    static let invitesKey = "um.invites.notify"
    static let prefix = "dm."

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var sound: Bool { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }
    static var preview: Bool { UserDefaults.standard.object(forKey: previewKey) as? Bool ?? true }

    static var isAppActive: Bool {
        #if canImport(UIKit)
        UIApplication.shared.applicationState == .active
        #else
        true
        #endif
    }

    /// Ask when the user turns DM notifications on. Calls back with whether alerts are allowed.
    static func requestPermission(_ done: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().delegate = ReadyNotificationDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                done(granted)
                if granted { UMPush.registerIfConfigured() }
            }
        }
    }

    /// Posts a DM alert unless: off, in a game, or the user is looking at that thread right now.
    /// `text` is nil when the server only sent `newNotif` (no message body for DMs).
    @MainActor
    static func post(channel: UMChatChannel?, sender: String?, text: String?, selfId: String?, inGame: Bool,
                     channelId: String? = nil) {
        guard enabled, !inGame else { return }
        guard let id = channel?.id ?? channelId else { return }
        let viewing = UMChatStore.shared.currentChannelId == id
        if viewing && isAppActive { return }
        let content = UNMutableNotificationContent()
        let who = sender ?? channel?.title(selfId: selfId)
        if preview {
            content.title = who ?? "Direct message"
            content.body = text ?? "New direct message"
        } else {
            content.title = "UltiMafia"
            content.body = "New direct message"
        }
        if sound { content.sound = .default }
        content.threadIdentifier = prefix + id
        content.userInfo = ["dmChannel": id]
        let request = UNNotificationRequest(identifier: prefix + id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func clear(channelId: String) {
        let c = UNUserNotificationCenter.current()
        c.removeDeliveredNotifications(withIdentifiers: [prefix + channelId])
    }

    /// Entering a game: drop every pending/delivered DM alert (no stale banners mid-game).
    static func clearAll() {
        let c = UNUserNotificationCenter.current()
        c.getDeliveredNotifications { list in
            let ids = list.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
            c.removeDeliveredNotifications(withIdentifiers: ids)
        }
        c.getPendingNotificationRequests { list in
            let ids = list.map(\.identifier).filter { $0.hasPrefix(prefix) }
            c.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Foreground banners for DMs (outside the open thread); other app alerts keep their old rule.
    static func foregroundOptions(for n: UNNotification) -> UNNotificationPresentationOptions {
        guard n.request.identifier.hasPrefix(prefix) || n.request.content.userInfo["dmChannel"] != nil else { return [] }
        return MainActor.assumeIsolated { UMChatStore.shared.inGame } ? [] : (sound ? [.banner, .sound, .list] : [.banner, .list])
    }

    /// Notification tap (local or remote): open that DM thread on the Messages tab.
    @MainActor
    static func handleTap(_ userInfo: [AnyHashable: Any]) {
        guard let id = userInfo["dmChannel"] as? String, !UMChatStore.shared.inGame else { return }
        UMChatStore.shared.focusChannelId = id
        NotificationCenter.default.post(name: .umOpenMessages, object: nil)
    }
}

extension Notification.Name {
    static let umOpenMessages = Notification.Name("umOpenMessages")
}

/// APNs client side for closed-app DM alerts. Inert until (1) Vinman enables the Push Notifications
/// capability (aps-environment entitlement) and provides the APNs key to the server, and (2) the server
/// exposes a device-token route (questions for Pranay). Flip `isConfigured` and set `registerPath` then.
enum UMPush {
    static let isConfigured = false
    /// e.g. "user/push/apns" (POST {token, environment, bundleId}). TBD by the server.
    static let registerPath: String? = nil
    /// e.g. "user/push/inGame" (POST {inGame}) so the server can suppress pushes mid-game. TBD.
    static let inGamePath: String? = nil
    static let tokenKey = "um.apns.token"

    @MainActor
    static func registerIfConfigured() {
        guard isConfigured else { return }
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    static func didRegister(token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        UMDiag.log("push", "apns token \(hex.prefix(8))…")
        guard let path = registerPath else { return }
        #if DEBUG
        let env = "development"
        #else
        let env = "production"
        #endif
        Task {
            try? await APIClient.shared.postStatus(path, json: [
                "token": hex, "environment": env, "bundleId": Bundle.main.bundleIdentifier ?? "",
            ])
        }
    }

    static func reportInGame(_ inGame: Bool) {
        guard isConfigured, let path = inGamePath else { return }
        Task { try? await APIClient.shared.postStatus(path, json: ["inGame": inGame]) }
    }
}

#if canImport(UIKit)
/// Remote-notification callbacks and launch-time notification delegate.
final class UMAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = ReadyNotificationDelegate.shared
        if UMDMNotify.enabled { UMPush.registerIfConfigured() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        UMPush.didRegister(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UMDiag.log("push", "apns register failed: \(error.localizedDescription)")
    }
}
#endif
