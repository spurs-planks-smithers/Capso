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
    /// A dev-only flag is always `off` in a release build. An override cannot
    /// turn it on there. The Jev flags are dev-only until there is a plan for
    /// a TypeSafe key on other people's Macs (Drew, 2026-10-24).
    public let devOnly: Bool

    public init(
        issue: Int,
        allowedStates: Set<FlagState>,
        devDefault: FlagState,
        releaseDefault: FlagState,
        releasedInBuild: Int?,
        devOnly: Bool = false
    ) {
        self.issue = issue
        self.allowedStates = allowedStates
        self.devDefault = devDefault
        self.releaseDefault = releaseDefault
        self.releasedInBuild = releasedInBuild
        self.devOnly = devOnly
    }

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
    case promptLanes
    case dataGuard
    /// Consent for capture images to leave the Mac in Jev requests.
    case jevSendImages
    /// Consent for screen text (OCR text, window titles, app names) to leave
    /// the Mac in Jev requests.
    case jevSendScreenText
    /// Zip Round and Zip N Selected in the Nshot menu (#85). Not a Jev
    /// feature, so it may turn on in a release build.
    case zipHandoff

    /// New flags start with both defaults `off`. A release default turns on
    /// only with a released-in build number.
    public var spec: FlagSpec {
        switch self {
        case .jevBase:
            FlagSpec(issue: 36, allowedStates: [.off, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .noteCoach:
            FlagSpec(issue: 37, allowedStates: [.off, .shadow, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .cropsAnchors:
            FlagSpec(issue: 38, allowedStates: [.off, .shadow, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .dupesConflicts:
            FlagSpec(issue: 39, allowedStates: [.off, .shadow, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .oneBreath:
            // Paused and locked off (Drew, 2026-10-24, #40). Add .shadow
            // back here and in the flags script to run the trial again.
            FlagSpec(issue: 40, allowedStates: [.off], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .promptLanes:
            FlagSpec(issue: 69, allowedStates: [.off, .shadow, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .dataGuard:
            FlagSpec(issue: 70, allowedStates: [.off, .shadow, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .jevSendImages:
            FlagSpec(issue: 36, allowedStates: [.off, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .jevSendScreenText:
            FlagSpec(issue: 36, allowedStates: [.off, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .zipHandoff:
            FlagSpec(issue: 85, allowedStates: [.off, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil)
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
    /// never needs a further fallback. A dev-only flag is `off` in a release
    /// build, whatever its override says.
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
        if spec.devOnly, channel == .release {
            return .off
        }
        if let text = override(key),
           let state = FlagState(rawValue: text),
           spec.allowedStates.contains(state) {
            return state
        }
        return spec.defaultState(for: channel)
    }
}
