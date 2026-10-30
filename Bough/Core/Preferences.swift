import Foundation

/// App-level preferences persisted in UserDefaults (not user documents).
enum AppPreferences {
    static let pullStrategyKey = "pullStrategy"
    static let diffFontSizeKey = "diffFontSize"
    static let signingKey = "commitSigning"

    /// Strategy used by single-click "Pull（默认）" and multi-repo batch pull.
    static var defaultPullStrategy: GitRepository.PullStrategy {
        get {
            UserDefaults.standard.string(forKey: pullStrategyKey)
                .flatMap(GitRepository.PullStrategy.init(rawValue:)) ?? .merge
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: pullStrategyKey) }
    }

    /// Monospaced diff body size (10...16).
    static var diffFontSize: Double {
        get { UserDefaults.standard.object(forKey: diffFontSizeKey) as? Double ?? 12 }
        set { UserDefaults.standard.set(newValue, forKey: diffFontSizeKey) }
    }

    /// Initial signing mode for the commit composer.
    static var defaultSigning: CommitSigning {
        get {
            UserDefaults.standard.string(forKey: signingKey)
                .flatMap(CommitSigning.init(rawValue:)) ?? .followConfig
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: signingKey) }
    }
}
