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
    /// The feature flag that this flag is a part of, or nil for a feature flag
    /// or a consent flag. A sub-flag runs at the lower of its own state and
    /// its parent's state (`FlagResolver.effectiveState`), so alone it runs
    /// nothing (Drew, 2026-10-25, #94).
    public let parent: FeatureFlag?

    public init(
        issue: Int,
        allowedStates: Set<FlagState>,
        devDefault: FlagState,
        releaseDefault: FlagState,
        releasedInBuild: Int?,
        devOnly: Bool = false,
        parent: FeatureFlag? = nil
    ) {
        self.issue = issue
        self.allowedStates = allowedStates
        self.devDefault = devDefault
        self.releaseDefault = releaseDefault
        self.releasedInBuild = releasedInBuild
        self.devOnly = devOnly
        self.parent = parent
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
/// `FLAGS=` line (and to its `SUBFLAGS=` line, for a sub-flag). A test fails
/// when the lists differ.
///
/// A sub-flag turns on one part of a feature, so Drew can judge that part
/// alone (Drew, 2026-10-25, #94). In the enum, a parent's sub-flags come
/// right after the parent.
public enum FeatureFlag: String, Sendable, CaseIterable {
    case jevBase
    case noteCoach
    /// Sub-flags of `noteCoach`: one per kind of line in the refined file.
    case noteCoachVague
    case noteCoachQuestion
    case noteCoachEmpty
    case cropsAnchors
    /// Sub-flags of `cropsAnchors`: the item crops, and the search lines.
    case cropsItemCrops
    case cropsSearchLines
    case dupesConflicts
    /// Sub-flags of `dupesConflicts`: the merged item, and the conflict block.
    case dupesMerge
    case dupesConflict
    case oneBreath
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
        case .noteCoachVague, .noteCoachQuestion, .noteCoachEmpty:
            Self.subFlagSpec(of: .noteCoach)
        case .cropsAnchors:
            FlagSpec(issue: 38, allowedStates: [.off, .shadow, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .cropsItemCrops, .cropsSearchLines:
            Self.subFlagSpec(of: .cropsAnchors)
        case .dupesConflicts:
            FlagSpec(issue: 39, allowedStates: [.off, .shadow, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .dupesMerge, .dupesConflict:
            Self.subFlagSpec(of: .dupesConflicts)
        case .oneBreath:
            // Paused and locked off (Drew, 2026-10-24, #40). Add .shadow
            // back here and in the flags script to run the trial again.
            FlagSpec(issue: 40, allowedStates: [.off], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .jevSendImages:
            FlagSpec(issue: 36, allowedStates: [.off, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .jevSendScreenText:
            FlagSpec(issue: 36, allowedStates: [.off, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil, devOnly: true)
        case .zipHandoff:
            FlagSpec(issue: 85, allowedStates: [.off, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil)
        }
    }

    /// A sub-flag starts off in both channels, allows every state, and is
    /// dev-only. It carries its parent's issue number.
    private static func subFlagSpec(of parent: FeatureFlag) -> FlagSpec {
        FlagSpec(
            issue: parent.spec.issue,
            allowedStates: [.off, .shadow, .on],
            devDefault: .off,
            releaseDefault: .off,
            releasedInBuild: nil,
            devOnly: true,
            parent: parent
        )
    }

    /// A feature flag's sub-flags, in registry order. Empty for any other flag.
    public static func subFlags(of parent: FeatureFlag) -> [FeatureFlag] {
        allCases.filter { $0.spec.parent == parent }
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

    /// The state a flag runs at. A sub-flag runs at the lower of its own state
    /// and its parent's state, in the order off, shadow, on. Any other flag
    /// runs at its own state. This is the one place that orders the states:
    /// the Jev runner and the app both use it.
    /// - Parameter state: Returns the resolved state of a flag, with the
    ///   dev-only rule applied, as `state(of:channel:override:)` does.
    public static func effectiveState(of flag: FeatureFlag, state: (FeatureFlag) -> FlagState) -> FlagState {
        let own = state(flag)
        guard let parent = flag.spec.parent else { return own }
        let capped = state(parent)
        return rank(capped) < rank(own) ? capped : own
    }

    private static func rank(_ state: FlagState) -> Int {
        switch state {
        case .off: 0
        case .shadow: 1
        case .on: 2
        }
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
