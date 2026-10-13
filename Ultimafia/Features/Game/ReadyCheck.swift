import Foundation
import SwiftUI
import UserNotifications
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif


/// AVAudioSession setCategory/setActive must not run on the main thread (Hang Risk).
enum UMAudioSession {
    private static let queue = DispatchQueue(label: "com.ultimafia.audiosession")

    /// Fire-and-forget, off the main thread. Always `.playback` + `.mixWithOthers` so Spotify /
    /// Apple Music keep playing under game sounds. Re-asserted on each call (cheap) in case another
    /// component changed the category; never deactivated, so other apps are never stopped by us.
    static func activatePlayback() {
        #if os(iOS)
        queue.async {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback || !session.categoryOptions.contains(.mixWithOthers) {
                try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try? session.setActive(true)
        }
        #endif
    }
}

enum ReadyBell {
    private static var player: AVAudioPlayer?
    private static var loadTask: Task<Void, Never>?

    static func start() {
        if player?.isPlaying == true { return }
        loadTask?.cancel()
        loadTask = Task { await play() }
    }

    static func stop() {
        loadTask?.cancel()
        loadTask = nil
        player?.stop()
        player = nil
    }

    static func applyVolume() {
        player?.volume = GameAudio.alert
    }

    @MainActor
    private static func play() async {
        activateSession()
        guard let url = await fileURL() else { return }
        guard !Task.isCancelled else { return }
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            next.numberOfLoops = -1
            next.volume = GameAudio.alert
            next.prepareToPlay()
            next.play()
            player = next
        } catch {}
    }

    private static func activateSession() {
        UMAudioSession.activatePlayback()
    }

    private static func fileURL() async -> URL? {
        let dest = UMCacheLocation.sounds
            .appendingPathComponent("um-urgent.mp3")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        guard let remote = URL(string: "https://ultimafia.com/audio/urgent.mp3") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: remote)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 { return nil }
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }
}


enum GameAudio {
    static let sfxKey = "um.sfxVolume"
    static let deathKey = "um.deathSoundVolume"
    static let musicKey = "um.musicVolume"
    /// Web settings.pregameMusicVolume: "music/Pregame*" tracks.
    static let pregameMusicKey = "um.pregameMusicVolume"
    /// Web settings.importantVolume ("Alert Volume"): bell, urgent (ready check), vegPing.
    static let alertKey = "um.alertVolume"
    static let alertSounds: Set<String> = ["bell", "urgent", "vegPing"]

    static func volume(_ key: String) -> Float {
        guard UserDefaults.standard.object(forKey: key) != nil else { return 1 }
        return Float(min(1, max(0, UserDefaults.standard.double(forKey: key))))
    }

    static var sfx: Float { volume(sfxKey) }
    static var death: Float { volume(deathKey) }
    static var music: Float { volume(musicKey) }
    static var pregameMusic: Float { volume(pregameMusicKey) }
    static var alert: Float { volume(alertKey) }
}

enum GameSFX {
    private static var playing: [AVAudioPlayer] = []
    private static var alertPlayers = Set<ObjectIdentifier>()
    private static var deathPlaying: [AVAudioPlayer] = []
    private static let localNames: Set<String> = ["bell", "gunshot", "ping"]

    static func applyVolume() {
        playing.forEach { $0.volume = alertPlayers.contains(ObjectIdentifier($0)) ? GameAudio.alert : GameAudio.sfx }
    }

    static func applyDeathVolume() {
        deathPlaying.forEach { $0.volume = GameAudio.death }
    }

    static func stopNonImportant() {
        playing.forEach { $0.stop() }
        playing.removeAll()
        deathPlaying.forEach { $0.stop() }
        deathPlaying.removeAll()
    }

    static func warm(_ name: String) {
        Task { _ = await fileURL(name) }
    }

    static func play(_ name: String) {
        let alert = GameAudio.alertSounds.contains(name)
        if let url = bundledURL(name) {
            playFile(url, alert: alert)
            return
        }
        Task { @MainActor in
            guard let url = await fileURL(name) else { return }
            playFile(url, alert: alert)
        }
    }

    static func playRemoteQueue(_ raws: [String]) {
        let urls = raws.compactMap(makeRemoteURL)
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            for url in urls {
                await playRemoteOnce(url)
            }
        }
    }

    @MainActor
    private static func playFile(_ url: URL, alert: Bool = false) {
        activateSession()
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            next.volume = alert ? GameAudio.alert : GameAudio.sfx
            next.prepareToPlay()
            next.play()
            playing.removeAll { !$0.isPlaying }
            alertPlayers = alertPlayers.filter { id in playing.contains { ObjectIdentifier($0) == id } }
            if alert { alertPlayers.insert(ObjectIdentifier(next)) }
            playing.append(next)
        } catch {}
    }

    @MainActor
    private static func playRemoteOnce(_ url: URL) async {
        activateSession()
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 { return }
            let next = try AVAudioPlayer(data: data)
            next.volume = GameAudio.death
            next.prepareToPlay()
            next.play()
            deathPlaying.removeAll { !$0.isPlaying }
            deathPlaying.append(next)
            let wait = min(next.duration, 6)
            if wait > 0.05 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        } catch {}
    }

    private static func activateSession() {
        UMAudioSession.activatePlayback()
    }

    private static func bundledURL(_ name: String) -> URL? {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        if let url = Bundle.main.url(forResource: safe, withExtension: "mp3") { return url }
        if let url = Bundle.main.url(forResource: safe, withExtension: "mp3", subdirectory: "Sounds") { return url }
        return nil
    }

    private static func supportURL(_ name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ultimafia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(safe).mp3")
    }

    private static func fileURL(_ name: String) async -> URL? {
        if let bundled = bundledURL(name) { return bundled }
        let dest = supportURL(name)
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        guard localNames.contains(name) else { return nil }
        guard let remote = URL(string: "https://ultimafia.com/audio/\(name).mp3") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: remote)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 { return nil }
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }

    nonisolated private static func makeRemoteURL(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return URL(string: s) }
        if s.hasPrefix("/") { return URL(string: "https://ultimafia.com" + s) }
        return URL(string: "https://ultimafia.com/" + s)
    }
}



enum GameMusic {
    private static var player: AVAudioPlayer?
    private static var current: String?
    private static var loadTask: Task<Void, Never>?

    static func handlePhase(_ name: String) {
        let n = name.lowercased()
        if n.contains("pregame") {
            playLoop("music/PregameSandbox")
        } else if n.hasPrefix("give clue") || n == "dawn" || n.contains("night") {
            playLoop("music/NightGeneric")
        } else if n.contains("post") {
            return
        } else {
            stop()
        }
    }

    static func playLoop(_ path: String) {
        if current == path, player?.isPlaying == true {
            applyVolume()
            return
        }
        current = path
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            await start(path)
        }
    }

    static func stop() {
        loadTask?.cancel()
        loadTask = nil
        player?.stop()
        player = nil
        current = nil
    }

    static func applyVolume() {
        player?.volume = volume(for: current)
    }

    private static func volume(for path: String?) -> Float {
        (path ?? "").hasPrefix("music/Pregame") ? GameAudio.pregameMusic : GameAudio.music
    }

    @MainActor
    private static func start(_ path: String) async {
        activateSession()
        guard let url = await fileURL(path) else { return }
        guard !Task.isCancelled, current == path else { return }
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            next.numberOfLoops = -1
            next.volume = volume(for: path)
            next.prepareToPlay()
            next.play()
            player?.stop()
            player = next
        } catch {}
    }

    private static func activateSession() {
        UMAudioSession.activatePlayback()
    }

    private static func fileURL(_ path: String) async -> URL? {
        let safe = path.replacingOccurrences(of: "/", with: "-")
        let dest = UMCacheLocation.sounds
            .appendingPathComponent("um-\(safe).mp3")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        guard let remote = URL(string: "https://ultimafia.com/audio/\(path).mp3") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: remote)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 { return nil }
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }
}

enum ReadyNotifications {
    static let id = "ultimafia.readyCheck"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        UNUserNotificationCenter.current().delegate = ReadyNotificationDelegate.shared
    }

    static func notifyIfBackgrounded() {
        guard !isAppActive else { return }
        let content = UNMutableNotificationContent()
        content.title = "Ultimafia"
        content.body = "Your game is starting! Accept ready check!"
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func clear() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    static var isAppActive: Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .active
        #elseif os(macOS)
        NSApplication.shared.isActive
        #else
        true
        #endif
    }
}

enum GameAlerts {
    static let mentionId = "ultimafia.mention"
    static let kicksId = "ultimafia.kicks"

    static func notifyMention() {
        post(id: mentionId, body: "Someone mentioned you! Come back!")
    }

    static func notifyKicks() {
        post(id: kicksId, body: "You are about to veg! The game is at kicks!")
    }

    private static func post(id: String, body: String) {
        guard !ReadyNotifications.isAppActive else { return }
        let content = UNMutableNotificationContent()
        content.title = "Ultimafia"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

final class ReadyNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReadyNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}

enum GameBackgroundHold {
    #if os(iOS)
    private static var task: UIBackgroundTaskIdentifier = .invalid
    #endif

    static func start() {
        #if os(iOS)
        end()
        task = UIApplication.shared.beginBackgroundTask(withName: "um-socket") {
            end()
        }
        #endif
    }

    static func end() {
        #if os(iOS)
        if task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        #endif
    }
}

struct ReadyCheckOverlay: View {
    var session: GameSession
    var onLeave: () -> Void

    var body: some View {
        if session.needsReadyConfirm {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Ready Up?")
                        .font(.title2.weight(.bold))
                    Text("The game is starting! Please confirm you are here.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.9))
                    TimelineView(.periodic(from: .now, by: 0.2)) { context in
                        let left = max(0, session.readyEndTime.timeIntervalSince(context.date))
                        Text("\(Int(left.rounded(.up)))s")
                            .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(left < 10 ? UMTheme.mafia : .white)
                    }
                    Text("Failure to ready up will result in being kicked.")
                        .font(.caption)
                        .foregroundStyle(UMTheme.muted)
                    HStack(spacing: 12) {
                        Button("Leave Game", role: .destructive) {
                            ReadyBell.stop()
                            onLeave()
                        }
                            .buttonStyle(.bordered)
                        Button("I am Ready") {
                            ReadyBell.stop()
                            session.verifyReady()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(UMTheme.village)
                        .background {
                            // Hardware Return/Enter accepts (listed in the Cmd-hold overlay).
                            Button("Accept Ready Check") { session.acceptReadyCheck() }
                                .keyboardShortcut(.return, modifiers: [])
                                .opacity(0)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(24)
                .frame(maxWidth: 360)
                .background(UMTheme.card, in: RoundedRectangle(cornerRadius: 18))
                .padding(28)
            }
            .onAppear { ReadyBell.start() }
            .onDisappear { ReadyBell.stop() }
        }
    }
}
