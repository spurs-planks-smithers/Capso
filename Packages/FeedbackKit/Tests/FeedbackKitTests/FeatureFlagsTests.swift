import Foundation
import Testing
@testable import FeedbackKit

/// The two registry rules, as functions of one spec. The tests run them on the
/// real registry and on bad specs, so a rule that stopped checking would fail.
private func releaseDefaultHasBuild(_ spec: FlagSpec) -> Bool {
    spec.releaseDefault == .off || spec.releasedInBuild != nil
}

private func defaultsAreAllowed(_ spec: FlagSpec) -> Bool {
    spec.allowedStates.contains(spec.devDefault) && spec.allowedStates.contains(spec.releaseDefault)
}

/// Allows off and shadow. Dev defaults to shadow and release to off, so the
/// channel changes the result.
private let channelSpec = FlagSpec(
    issue: 1,
    allowedStates: [.off, .shadow],
    devDefault: .shadow,
    releaseDefault: .off,
    releasedInBuild: nil
)

private func resolve(_ channel: BuildChannel, override: String?) -> FlagState {
    FlagResolver.resolve(channelSpec, key: "flag.test", channel: channel) { _ in override }
}

@Suite("FeatureFlags")
struct FeatureFlagsTests {
    @Test("Lists the fifteen flags with their issue numbers")
    func registryContents() {
        #expect(FeatureFlag.allCases.map(\.rawValue) == [
            "jevBase", "noteCoach", "noteCoachVague", "noteCoachQuestion", "noteCoachEmpty",
            "cropsAnchors", "cropsItemCrops", "cropsSearchLines",
            "dupesConflicts", "dupesMerge", "dupesConflict",
            "oneBreath", "jevSendImages", "jevSendScreenText", "zipHandoff",
        ])
        // A sub-flag carries its parent's issue. The two consent flags belong
        // to the Jev base, #36.
        #expect(FeatureFlag.allCases.map(\.spec.issue) == [36, 37, 37, 37, 37, 38, 38, 38, 39, 39, 39, 40, 36, 36, 85])
    }

    /// The sub-flags of the Jev features, by parent (#94).
    private static let subFlagsByParent: [(parent: FeatureFlag, subs: [FeatureFlag])] = [
        (.noteCoach, [.noteCoachVague, .noteCoachQuestion, .noteCoachEmpty]),
        (.cropsAnchors, [.cropsItemCrops, .cropsSearchLines]),
        (.dupesConflicts, [.dupesMerge, .dupesConflict]),
    ]

    private static let subFlags: [FeatureFlag] = FeatureFlag.allCases.filter { $0.spec.parent != nil }

    @Test("Each feature lists its sub-flags in registry order, and the sub-flags follow the parent")
    func subFlagLists() throws {
        for (parent, subs) in Self.subFlagsByParent {
            #expect(FeatureFlag.subFlags(of: parent) == subs, "\(parent)")
            let start = try #require(FeatureFlag.allCases.firstIndex(of: parent))
            #expect(Array(FeatureFlag.allCases[(start + 1)...].prefix(subs.count)) == subs, "\(parent) is not followed by its sub-flags")
        }
        // A sub-flag, a consent flag, and a feature with no sub-flags have none.
        for flag in [FeatureFlag.noteCoachVague, .jevSendImages, .jevBase, .oneBreath, .zipHandoff] {
            #expect(FeatureFlag.subFlags(of: flag).isEmpty, "\(flag)")
        }
        // The list above covers every sub-flag in the registry.
        try #require(!Self.subFlags.isEmpty)
        #expect(Set(Self.subFlags) == Set(Self.subFlagsByParent.flatMap(\.subs)))
    }

    @Test("Every sub-flag is dev-only, starts off in both channels, allows every state, and has a parent with its issue")
    func subFlagSpecs() throws {
        try #require(!Self.subFlags.isEmpty, "the registry has no sub-flags")
        for flag in Self.subFlags {
            let spec = flag.spec
            #expect(spec.devOnly, "\(flag) can turn on in a release build")
            #expect(spec.devDefault == .off && spec.releaseDefault == .off, "\(flag) does not start off")
            #expect(spec.allowedStates == [.off, .shadow, .on], "\(flag)")
            #expect(spec.releasedInBuild == nil, "\(flag)")
            let parent = try #require(spec.parent, "\(flag) has no parent")
            #expect(spec.issue == parent.spec.issue, "\(flag) does not carry its parent's issue")
            // One level only: a parent is a feature flag, not a sub-flag.
            #expect(parent.spec.parent == nil, "\(flag) has a parent that is a sub-flag")
            #expect(!FeatureFlag.subFlags(of: parent).isEmpty)
        }
    }

    @Test("A sub-flag runs at the lower of its own state and its parent's, for all nine pairs")
    func subFlagCap() {
        let order: [FlagState] = [.off, .shadow, .on]
        var checked = 0
        for (parent, subs) in Self.subFlagsByParent {
            for sub in subs {
                for own in order {
                    for capped in order {
                        let lookup: (FeatureFlag) -> FlagState = { $0 == sub ? own : capped }
                        let lower = order[min(order.firstIndex(of: own)!, order.firstIndex(of: capped)!)]
                        #expect(FlagResolver.effectiveState(of: sub, state: lookup) == lower, "\(sub) \(own) under \(parent) \(capped)")
                        checked += 1
                    }
                }
            }
        }
        #expect(checked == Self.subFlags.count * 9, "the cap loop skipped a pair")
    }

    @Test("A flag with no parent runs at its own state, whatever other flags say")
    func noParentNoCap() {
        for flag in FeatureFlag.allCases where flag.spec.parent == nil {
            for own in FlagState.allCases {
                let lookup: (FeatureFlag) -> FlagState = { $0 == flag ? own : .off }
                #expect(FlagResolver.effectiveState(of: flag, state: lookup) == own, "\(flag) \(own)")
            }
        }
    }

    @Test("Through the resolver: a sub-flag alone is off, and a release build reads every sub-flag as off")
    func subFlagThroughResolver() {
        func effective(_ flag: FeatureFlag, _ channel: BuildChannel, overrides: [FeatureFlag: String]) -> FlagState {
            FlagResolver.effectiveState(of: flag) { FlagResolver.state(of: $0, channel: channel) { key in overrides.first { $0.key.overrideKey == key }?.value } }
        }
        // The sub-flag alone, with its parent at the default (off).
        #expect(effective(.noteCoachVague, .dev, overrides: [.noteCoachVague: "on"]) == .off)
        // The parent alone gives the sub-flag nothing.
        #expect(effective(.noteCoachVague, .dev, overrides: [.noteCoach: "on"]) == .off)
        // Both set: the lower wins.
        #expect(effective(.noteCoachVague, .dev, overrides: [.noteCoach: "shadow", .noteCoachVague: "on"]) == .shadow)
        #expect(effective(.noteCoachVague, .dev, overrides: [.noteCoach: "on", .noteCoachVague: "on"]) == .on)
        // A release build ignores both overrides.
        #expect(effective(.noteCoachVague, .release, overrides: [.noteCoach: "on", .noteCoachVague: "on"]) == .off)
    }

    /// Flags that are not Jev features. They may turn on in a release build.
    private static let nonJevFlags: Set<FeatureFlag> = [.zipHandoff]

    @Test("The zip handoff flag is not dev-only and starts off")
    func zipHandoffFlag() {
        let spec = FeatureFlag.zipHandoff.spec
        #expect(spec.issue == 85)
        #expect(spec.devOnly == false)
        #expect(spec.allowedStates == [.off, .on])
        #expect(spec.devDefault == .off)
        #expect(spec.releaseDefault == .off)
        // Not dev-only: an override turns it on in a release build too.
        #expect(FlagResolver.state(of: .zipHandoff, channel: .release) { _ in "on" } == .on)
        #expect(FlagResolver.state(of: .zipHandoff, channel: .release) { _ in nil } == .off)
    }

    @Test("Every Jev flag is dev-only, and a dev-only flag defaults to off in release")
    func jevFlagsAreDevOnly() {
        for flag in FeatureFlag.allCases where !Self.nonJevFlags.contains(flag) {
            #expect(flag.spec.devOnly, "\(flag) can turn on in a release build")
            #expect(flag.spec.releaseDefault == .off, "\(flag) is dev-only but on in release")
        }
    }

    @Test("A release build ignores every override of a dev-only flag")
    func devOnlyIgnoresReleaseOverride() {
        for flag in FeatureFlag.allCases where flag.spec.devOnly {
            for state in flag.spec.allowedStates {
                #expect(FlagResolver.state(of: flag, channel: .release) { _ in state.rawValue } == .off, "\(flag) \(state) in release")
                #expect(FlagResolver.state(of: flag, channel: .dev) { _ in state.rawValue } == state, "\(flag) \(state) in dev")
            }
        }
    }

    @Test("Names the override key flag.<name>")
    func overrideKeyFormat() {
        #expect(FeatureFlag.noteCoach.overrideKey == "flag.noteCoach")
        #expect(FeatureFlag.jevBase.overrideKey == "flag.jevBase")
    }

    @Test("A release default that is not off needs a released-in build number")
    func releaseDefaultNeedsBuild() {
        for flag in FeatureFlag.allCases {
            #expect(releaseDefaultHasBuild(flag.spec), "\(flag) turns on in release with no released-in build")
        }
        // The rule rejects a bad spec and accepts a good one.
        let bad = FlagSpec(issue: 1, allowedStates: [.off, .on], devDefault: .on, releaseDefault: .on, releasedInBuild: nil)
        let good = FlagSpec(issue: 1, allowedStates: [.off, .on], devDefault: .on, releaseDefault: .on, releasedInBuild: 520)
        #expect(!releaseDefaultHasBuild(bad))
        #expect(releaseDefaultHasBuild(good))
    }

    @Test("Every default is one of the flag's allowed states")
    func defaultsAreAllowedStates() {
        for flag in FeatureFlag.allCases {
            #expect(defaultsAreAllowed(flag.spec), "\(flag) has a default it does not allow")
        }
        let bad = FlagSpec(issue: 1, allowedStates: [.off, .shadow], devDefault: .on, releaseDefault: .off, releasedInBuild: nil)
        #expect(!defaultsAreAllowed(bad))
    }

    @Test("With no override, the channel decides")
    func channelDefault() {
        #expect(resolve(.dev, override: nil) == .shadow)
        #expect(resolve(.release, override: nil) == .off)
    }

    @Test("An allowed override beats the channel default in both channels")
    func overrideWins() {
        #expect(resolve(.dev, override: "off") == .off)
        #expect(resolve(.release, override: "shadow") == .shadow)
    }

    @Test("An unknown or disallowed override reads as the channel default")
    func badOverrideIsIgnored() {
        for bad in ["on", "banana", "", "ON", " shadow"] {
            #expect(resolve(.dev, override: bad) == .shadow, "dev with '\(bad)'")
            #expect(resolve(.release, override: bad) == .off, "release with '\(bad)'")
        }
    }

    @Test("A real flag asks for its own key and ignores a state it does not allow")
    func realFlagLookup() {
        var asked: [String] = []
        let state = FlagResolver.state(of: .oneBreath, channel: .dev) { key in
            asked.append(key)
            return "on"
        }
        #expect(asked == ["flag.oneBreath"])
        #expect(state != .on, "oneBreath never allows on")

        let noteCoach = FlagResolver.state(of: .noteCoach, channel: .dev) { _ in "on" }
        #expect(noteCoach == .on)
        let jevBase = FlagResolver.state(of: .jevBase, channel: .dev) { _ in "shadow" }
        #expect(jevBase != .shadow, "jevBase never allows shadow")
    }

    /// The entries of a `NAME="<key>:<values> ..."` line in the script, in
    /// order. A value list splits at commas. The line must appear once.
    private func scriptEntries(_ name: String) throws -> [(key: String, values: [String])] {
        // .../Packages/FeedbackKit/Tests/FeedbackKitTests/FeatureFlagsTests.swift
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let script = try String(contentsOf: root.appendingPathComponent("scripts/nextshot-flags.sh"), encoding: .utf8)

        let lines = script.split(separator: "\n").filter { $0.hasPrefix("\(name)=") }
        #expect(lines.count == 1, "the script needs exactly one \(name)= line")
        let value = lines.first?.dropFirst("\(name)=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? ""

        var entries: [(key: String, values: [String])] = []
        for entry in value.split(separator: " ") {
            let parts = entry.split(separator: ":", maxSplits: 1)
            #expect(parts.count == 2, "bad \(name) entry '\(entry)'")
            if parts.count == 2 {
                entries.append((String(parts[0]), parts[1].split(separator: ",").map(String.init)))
            }
        }
        return entries
    }

    @Test("scripts/nextshot-flags.sh lists every flag with its allowed states, in registry order")
    func scriptMatchesRegistry() throws {
        let listed = try scriptEntries("FLAGS")
        // A parser that reads nothing must fail, not pass.
        try #require(!listed.isEmpty, "the parser read no flags from the FLAGS= line")

        #expect(listed.map(\.key) == FeatureFlag.allCases.map(\.rawValue))
        for flag in FeatureFlag.allCases {
            let allowed = Set(flag.spec.allowedStates.map(\.rawValue))
            let entry = listed.first { $0.key == flag.rawValue }
            #expect(entry.map { Set($0.values) } == allowed, "\(flag) differs between the script and the registry")
        }
    }

    @Test("scripts/nextshot-flags.sh lists every parent with its sub-flags, in registry order")
    func scriptMatchesSubFlags() throws {
        let listed = try scriptEntries("SUBFLAGS")
        try #require(!listed.isEmpty, "the parser read no parents from the SUBFLAGS= line")

        let expected = FeatureFlag.allCases.filter { !FeatureFlag.subFlags(of: $0).isEmpty }
        try #require(!expected.isEmpty, "the registry has no parents")
        #expect(listed.map(\.key) == expected.map(\.rawValue))
        for parent in expected {
            let entry = listed.first { $0.key == parent.rawValue }
            #expect(entry?.values == FeatureFlag.subFlags(of: parent).map(\.rawValue), "\(parent) differs between the script and the registry")
        }
    }
}
