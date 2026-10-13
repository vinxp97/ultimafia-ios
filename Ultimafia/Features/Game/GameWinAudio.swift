import Foundation
import AVFoundation

enum GameWinMusic {
    private static var playing: [AVAudioPlayer] = []

    static func unlockSession() {
        activateSession()
    }

    static func warmCommon() {
        for name in ["WinMafia", "WinVillage", "WinCult", "Draw"] {
            _ = bundledURL(name)
        }
    }

    static func applyVolume() {
        playing.forEach { $0.volume = GameAudio.music }
    }

    static func stop() {
        UMAudioSession.stop(playing)
        playing.removeAll()
    }

    static func stopNonImportant() {
        GameMusic.stop()
        stop()
        GameSFX.stopNonImportant()
    }

    static func playWinners(_ groups: [String]) {
        stopNonImportant()
        let hasMafia = groups.contains("Mafia")
        var seen = Set<String>()
        for group in groups {
            guard seen.insert(group).inserted else { continue }
            if group == "No one" {
                if !hasMafia { playWin("Draw") }
                continue
            }
            if let file = Self.trackName(for: group) {
                playWin(file)
            }
        }
    }

    private static func trackName(for group: String) -> String? {
        switch group {
        case "Alien": return "WinAlien"
        case "Blob": return "WinBlob"
        case "Prophet": return "WinProphet"
        case "Fool": return "WinFool"
        case "Dodo": return "WinDodo"
        case "Joker": return "WinJoker"
        default: return extraTrackName(group)
        }
    }

    static func playWin(_ fileName: String) {
        guard let url = bundledURL(fileName) else { return }
        let volume = GameAudio.music
        Task { @MainActor in
            guard let next = await UMAudioSession.startPlayer(fileName, volume: volume, make: {
                try AVAudioPlayer(contentsOf: url)
            }) else { return }
            playing.removeAll { !$0.isPlaying }
            playing.append(next)
        }
    }

    private static func bundledURL(_ name: String) -> URL? {
        let stem = name.replacingOccurrences(of: "music/", with: "")
        let safe = stem.replacingOccurrences(of: "/", with: "-")
        if let url = Bundle.main.url(forResource: safe, withExtension: "mp3") { return url }
        if let url = Bundle.main.url(forResource: safe, withExtension: "mp3", subdirectory: "Sounds") { return url }
        return nil
    }

    private static func activateSession() {
        UMAudioSession.activatePlayback()
    }
}
