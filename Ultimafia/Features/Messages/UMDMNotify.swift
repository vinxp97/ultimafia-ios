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
        guard UMNotifyMaster.isOn, enabled, !inGame else { return }
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

/// APNs for closed-app DM alerts. Server: POST/DELETE /api/user/push/apns {token, environment, bundleId}
/// (login required; the server skips pushes while the user is playing or spectating).
/// Registers only when signed in AND DM alerts are on with notification permission granted.
enum UMPush {
    static let isConfigured = UMFeatureFlags.pushNotificationsEnabled
    static let registerPath = "user/push/apns"
    static let tokenKey = "um.apns.token"
    static let bundleId = "VCCCLLC.Ultimafia"
    #if DEBUG
    static let environment = "development"
    #else
    static let environment = "production"
    #endif

    /// Set by the signed-in shell; uploads wait for it.
    @MainActor static var signedIn = false
    @MainActor private static var uploadedToken: String?

    /// Call after login and after DM alerts are enabled.
    @MainActor
    static func registerIfConfigured() {
        guard isConfigured, signedIn, UMNotifyMaster.isOn, UMDMNotify.enabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            guard s.authorizationStatus == .authorized || s.authorizationStatus == .provisional else { return }
            Task { @MainActor in
                #if canImport(UIKit)
                UIApplication.shared.registerForRemoteNotifications()
                #endif
            }
        }
    }

    @MainActor
    static func didRegister(token: Data) {
        guard isConfigured else { return }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        UMDiag.log("push", "apns token \(hex.prefix(8))… env \(environment)")
        upload(hex)
    }

    @MainActor
    private static func upload(_ hex: String) {
        guard isConfigured, signedIn, UMDMNotify.enabled, uploadedToken != hex else { return }
        uploadedToken = hex
        Task {
            do {
                try await APIClient.shared.postStatus(registerPath, json: body(hex))
                UMDiag.log("push", "token registered")
            } catch {
                UMDiag.log("push", "token register failed: \(error.localizedDescription)")
                await MainActor.run { uploadedToken = nil }
            }
        }
    }

    private static func body(_ hex: String) -> [String: Any] {
        ["token": hex, "environment": environment, "bundleId": bundleId]
    }

    /// Logout, account switch, or DM alerts turned off: remove this device from the current account.
    /// Must run while the old session is still valid.
    @MainActor
    static func unregister() async {
        guard isConfigured, let hex = UserDefaults.standard.string(forKey: tokenKey) else { return }
        uploadedToken = nil
        _ = try? await APIClient.shared.request("DELETE", path: registerPath, query: [:], body: body(hex))
        UMDiag.log("push", "token unregistered")
    }

    /// The server checks game membership itself, so nothing to report.
    static func reportInGame(_ inGame: Bool) {}
}

#if canImport(UIKit)
/// Remote-notification callbacks and launch-time notification delegate.
final class UMAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = ReadyNotificationDelegate.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { UMPush.didRegister(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UMDiag.log("push", "apns register failed: \(error.localizedDescription)")
    }
}
#endif


/// Device-wide master switch for ALL app notifications (DM alerts, ready check, mentions, kicks alerts,
/// and APNs registration when UMFeatureFlags allows it). Plain UserDefaults: shared by every account.
/// The Live Activity is not a notification and ignores this.
enum UMNotifyMaster {
    nonisolated static let key = "um.notifications.master"
    nonisolated static let didAskKey = "um.notifications.didAskFirstLaunch"

    nonisolated static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    @MainActor static func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
        if on { UMPush.registerIfConfigured() } else { Task { await UMPush.unregister() } }
    }

    @MainActor private static var observing = false

    /// App launch: delegate, one-time permission ask, and foreground re-sync.
    @MainActor static func launch() {
        UNUserNotificationCenter.current().delegate = ReadyNotificationDelegate.shared
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                   object: nil, queue: .main) { _ in
                Task { @MainActor in resync() }
            }
        }
        if !UserDefaults.standard.bool(forKey: didAskKey) {
            UserDefaults.standard.set(true, forKey: didAskKey)
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                Task { @MainActor in set(granted) }
            }
        } else {
            resync()
        }
    }

    /// System permission revoked in Settings -> show the toggle off.
    @MainActor static func resync() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            #if os(macOS)
            let allowed = [.authorized, .provisional].contains(s.authorizationStatus)
            #else
            let allowed = [.authorized, .provisional, .ephemeral].contains(s.authorizationStatus)
            #endif
            Task { @MainActor in if !allowed && isOn { set(false) } }
        }
    }

    enum Outcome { case on, denied, off }

    /// User turned the toggle on.
    @MainActor static func requestOn(_ done: @escaping @MainActor (Outcome) -> Void) {
        let c = UNUserNotificationCenter.current()
        c.getNotificationSettings { s in
            switch s.authorizationStatus {
            case .denied:
                Task { @MainActor in set(false); done(.denied) }
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    Task { @MainActor in set(granted); done(granted ? .on : .off) }
                }
            default:
                Task { @MainActor in set(true); done(.on) }
            }
        }
    }

    @MainActor static func openSettings() {
        let s = URL(string: UIApplication.openNotificationSettingsURLString) ?? URL(string: UIApplication.openSettingsURLString)
        if let s { UIApplication.shared.open(s) }
    }
}
