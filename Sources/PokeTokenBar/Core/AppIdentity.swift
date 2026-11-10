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
    /// Update checks are off: the upstream repository publishes PokeTokenBar releases, not ours.
    static let updateRepo: String? = nil
}
