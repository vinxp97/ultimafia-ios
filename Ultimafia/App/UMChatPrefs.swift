import Foundation

/// Chat input preferences shared by every composer (iPhone, iPad, Mac).
nonisolated enum UMChatPrefs {
    /// "Space after autocomplete" (You > chat settings; Mac Settings > Chat). Default on: a
    /// completed @name, %avatar, @everyone, slash command/target or :emote:/;sticker; is followed
    /// by a space. Off: the completion is inserted with nothing after it.
    static let spaceAfterAutocompleteKey = "um.spaceAfterAutocomplete"

    static var spaceAfterAutocomplete: Bool {
        UserDefaults.standard.object(forKey: spaceAfterAutocompleteKey) as? Bool ?? true
    }

    /// What follows an inserted completion: " " or "".
    static var completionSuffix: String { spaceAfterAutocomplete ? " " : "" }
}
