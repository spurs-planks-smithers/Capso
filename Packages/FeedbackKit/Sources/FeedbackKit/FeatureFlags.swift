// Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift
import Foundation

/// How far a feature runs. `shadow` runs the new code path without showing
/// its result to the user. Each feature defines what that means for itself.
public enum FlagState: String, Sendable, CaseIterable {
    case off
    case shadow
    case on
}

/// The kind of build. The app reads it from its own code signature.
public enum BuildChannel: String, Sendable {
    /// Xcode, `scripts/build-local.sh`, and test builds.
    case dev
    /// `scripts/release-notarized.sh`, the DMG on nextshot.dev.
    case release
}

/// One flag's registry entry.
public struct FlagSpec: Sendable, Equatable {
    /// The GitHub issue that tracks the feature.
    public let issue: Int
    public let allowedStates: Set<FlagState>
    public let devDefault: FlagState
    public let releaseDefault: FlagState
    /// The build number where the release default turned on. A release
    /// default other than `off` needs one.
    public let releasedInBuild: Int?

    public func defaultState(for channel: BuildChannel) -> FlagState {
        switch channel {
        case .dev: devDefault
        case .release: releaseDefault
        }
    }
}

/// Every feature flag. This is the one registry: a new flag adds a case here
/// and an entry in `spec`, and `scripts/nextshot-flags.sh` adds it to its
/// `FLAGS=` line. A test fails when the two lists differ.
public enum FeatureFlag: String, Sendable, CaseIterable {
    case jevBase
    case noteCoach
    case cropsAnchors
    case dupesConflicts
    case oneBreath

    /// New flags start with both defaults `off`. A release default turns on
    /// only with a released-in build number.
    public var spec: FlagSpec {
        switch self {
        case .jevBase:
            FlagSpec(issue: 36, allowedStates: [.off, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil)
        case .noteCoach:
            FlagSpec(issue: 37, allowedStates: [.off, .shadow, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil)
        case .cropsAnchors:
            FlagSpec(issue: 38, allowedStates: [.off, .shadow, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil)
        case .dupesConflicts:
            FlagSpec(issue: 39, allowedStates: [.off, .shadow, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil)
        case .oneBreath:
            FlagSpec(issue: 40, allowedStates: [.off, .shadow], devDefault: .off, releaseDefault: .off, releasedInBuild: nil)
        }
    }

    /// The UserDefaults key for this flag's local override, for example
    /// `flag.noteCoach`.
    public var overrideKey: String { "flag.\(rawValue)" }
}

public enum FlagResolver {
    /// A local override wins, then the channel default. An override that is
    /// missing, unknown, or not allowed for the flag is ignored. Every flag
    /// has a default for each channel, so a flag with no usable override
    /// never needs a further fallback.
    /// - Parameter override: Returns the stored string for a key, or nil.
    public static func state(
        of flag: FeatureFlag,
        channel: BuildChannel,
        override: (String) -> String?
    ) -> FlagState {
        resolve(flag.spec, key: flag.overrideKey, channel: channel, override: override)
    }

    /// The lookup on its own, so a test can pass a spec whose dev and release
    /// defaults differ.
    static func resolve(
        _ spec: FlagSpec,
        key: String,
        channel: BuildChannel,
        override: (String) -> String?
    ) -> FlagState {
        if let text = override(key),
           let state = FlagState(rawValue: text),
           spec.allowedStates.contains(state) {
            return state
        }
        return spec.defaultState(for: channel)
    }
}
