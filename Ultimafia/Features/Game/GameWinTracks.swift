import Foundation

extension GameWinMusic {
    static func extraTrackName(_ group: String) -> String? {
        switch group {
        case "Village": return "WinVillage"
        case "Cult": return "WinCult"
        case "Angel": return "WinAngel"
        case "Siren": return "WinSiren"
        case "Monk": return "WinMonk"
        case "Lover": return "WinLover"
        case "Astrologer": return "WinAstrologer"
        case "Hellhound": return "WinHellhound"
        case "Warlock": return "WinWarlock"
        case "Autocrat": return "WinAutocrat"
        case "Gambler": return "WinGambler"
        case "Sidekick": return "WinSidekick"
        case "Executioner": return "WinExecutioner"
        case "Clockmaker": return "WinClockmaker"
        case "Mastermind": return "WinMastermind"
        case "Communist": return "WinCommunist"
        case "Pyromaniac": return "WinPyromaniac"
        case "Matchmaker": return "WinMatchmaker"
        case "Survivor": return "WinSurvivor"
        case "Mafia": return "WinMafia"
        case "Serial Killer": return "WinKiller"
        case "Creepy Girl": return "WinCreepyGirl"
        case "Grey Goo": return "WinGreyGoo"
        case "Puppeteer": return "WinPuppeteer"
        default: return nil
        }
    }
}
