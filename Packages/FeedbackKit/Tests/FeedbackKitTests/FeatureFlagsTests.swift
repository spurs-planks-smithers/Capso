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
    @Test("Lists the ten flags with their issue numbers")
    func registryContents() {
        #expect(FeatureFlag.allCases.map(\.rawValue) == [
            "jevBase", "noteCoach", "cropsAnchors", "dupesConflicts", "oneBreath", "promptLanes", "dataGuard",
            "jevSendImages", "jevSendScreenText", "zipHandoff",
        ])
        // The two consent flags belong to the Jev base, #36.
        #expect(FeatureFlag.allCases.map(\.spec.issue) == [36, 37, 38, 39, 40, 69, 70, 36, 36, 85])
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

    @Test("scripts/nextshot-flags.sh lists every flag with its allowed states")
    func scriptMatchesRegistry() throws {
        // .../Packages/FeedbackKit/Tests/FeedbackKitTests/FeatureFlagsTests.swift
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let script = try String(contentsOf: root.appendingPathComponent("scripts/nextshot-flags.sh"), encoding: .utf8)

        let lines = script.split(separator: "\n").filter { $0.hasPrefix("FLAGS=") }
        #expect(lines.count == 1, "the script needs exactly one FLAGS= line")
        let value = lines.first?.dropFirst("FLAGS=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? ""

        var listed: [String: Set<String>] = [:]
        for entry in value.split(separator: " ") {
            let parts = entry.split(separator: ":", maxSplits: 1)
            #expect(parts.count == 2, "bad FLAGS entry '\(entry)'")
            if parts.count == 2 {
                listed[String(parts[0])] = Set(parts[1].split(separator: ",").map(String.init))
            }
        }
        // A parser that reads nothing must fail, not pass.
        try #require(!listed.isEmpty, "the parser read no flags from the FLAGS= line")

        #expect(Set(listed.keys) == Set(FeatureFlag.allCases.map(\.rawValue)))
        for flag in FeatureFlag.allCases {
            let allowed = Set(flag.spec.allowedStates.map(\.rawValue))
            #expect(listed[flag.rawValue] == allowed, "\(flag) differs between the script and the registry")
        }
    }
}
