import Foundation

/// Names that keep DigiTokenBar apart from an installed PokeTokenBar: its own data folder, logs,
/// URL scheme and login item. The Swift target is still called `PokeTokenBar` so upstream changes
/// keep merging cleanly; only these runtime names change.
enum AppIdentity {
    static let name = "DigiTokenBar"
    static let bundleID = "io.github.deadlylaid.digitokenbar"
    /// Folder under ~/Library/Application Support.
    static let stateFolder = "DigiTokenBar"
    /// File name stem under ~/Library/Logs.
    static let logFileStem = "DigiTokenBar"
    static let urlScheme = "digitokenbar"
    static let loginAgentLabel = "io.github.deadlylaid.digitokenbar.login"
    /// GitHub repository whose latest release the update check reads (its release page opens on update).
    static let updateRepo: String? = "deadlylaid/DigiTokenBar"
    /// Homebrew cask that "Update" may upgrade. DigiTokenBar has none: the old hard-coded value,
    /// `poke-token-bar`, is the upstream app, so on a Mac with PokeTokenBar from Homebrew the update
    /// button would have upgraded and reopened the wrong app. nil makes every update open the release page.
    static let homebrewCask: String? = nil
}
