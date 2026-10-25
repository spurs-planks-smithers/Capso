import FeedbackKit
import Foundation
import Testing
@testable import JevKit

// The runner reads a sub-flag at the lower of its own state and its parent's
// (#94). The gate treats a feature as on only when one of its sub-flags is on
// after that cap. These tests run the real runner on a real round on disk.

/// Holds what a test job saw, across the runner's task boundary.
private actor CapSeen {
    var modes: [FeatureFlag: FlagState]?

    func record(_ modes: [FeatureFlag: FlagState]) {
        self.modes = modes
    }
}

/// A job that declares options and records the modes it gets.
private struct CapJob: JevJob {
    var id: String
    var flag: FeatureFlag
    var options: [FeatureFlag]
    var version = 1
    let requires: JevDataKinds = []
    let seen: CapSeen

    func run(_ context: JevJobContext) async throws -> JevJobOutput {
        await seen.record(context.optionModes)
        return .empty
    }
}

private let order: [FlagState] = [.off, .shadow, .on]

private func lower(_ first: FlagState, _ second: FlagState) -> FlagState {
    order[min(order.firstIndex(of: first)!, order.firstIndex(of: second)!)]
}

@Suite("Sub-flag cap in the runner")
struct SubFlagCapTests {
    @Test("A sub-flag reaches the job at the lower of its state and the job flag's, and a job with every option off does not run")
    func capForAllNinePairs() async throws {
        var ran = 0
        for parent in order {
            for sub in order {
                let bundle = try await Bundle.make()
                let seen = CapSeen()
                let job = CapJob(id: "noteCoach", flag: .noteCoach, options: [.noteCoachVague], seen: seen)
                let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .noteCoach: parent, .noteCoachVague: sub]
                await runCapture(makeRunner(bundle, jobs: [job], flags: flags), bundle)

                let capped = lower(sub, parent)
                if capped == .off {
                    // The job flag is off, or its only option is off after the cap: nothing to do.
                    #expect(await seen.modes == nil, "parent \(parent), sub \(sub) ran")
                } else {
                    #expect(await seen.modes == [.noteCoachVague: capped], "parent \(parent), sub \(sub)")
                    ran += 1
                }
            }
        }
        #expect(ran == 4, "the loop skipped a pair")
    }

    @Test("A sub-flag alone starts nothing: no request, no key read, no jev.json")
    func subFlagAloneRunsNothing() async throws {
        let bundle = try await Bundle.make()
        let transport = StubTransport()
        let key = StubKeyProvider()
        let seen = CapSeen()
        let flags: [FeatureFlag: FlagState] = [
            .jevBase: .on, .noteCoachVague: .on, .noteCoachQuestion: .on, .noteCoachEmpty: .on,
            .cropsItemCrops: .on, .cropsSearchLines: .on, .jevSendImages: .on, .jevSendScreenText: .on,
        ]
        let jobs: [any JevJob] = [
            NoteCoachJob(), CropsAnchorsJob(),
            CapJob(id: "noteCoach", flag: .noteCoach, options: [.noteCoachVague], seen: seen),
        ]
        await runCapture(makeRunner(bundle, jobs: jobs, flags: flags, transport: transport, key: key), bundle)

        #expect(await transport.count == 0)
        #expect(await key.reads == 0)
        #expect(!bundle.exists("jev.json"))
        #expect(await seen.modes == nil)
    }

    /// Runs `job` with its feature flag at `state` and every sub-flag off, with
    /// every consent on. Nothing may start: no key read, no stored work, no
    /// request, no file, and no wait at round end.
    private func expectNothingStarts(_ job: any JevJob, state: FlagState, captures: Int = 1) async throws {
        let flag = job.flag
        let bundle = try await Bundle.make(captures: captures)
        let transport = StubTransport(fallback: jsonResponse(noulBody("1.1.names_change")))
        let key = StubKeyProvider()
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, flag: state, .jevSendImages: .on, .jevSendScreenText: .on]
        let runner = makeRunner(bundle, jobs: [job], flags: flags, transport: transport, key: key)
        // The last capture is the one that has earlier entries to compare with.
        await runner.warmUp()
        await runner.expect(folderName: bundle.folderName, capture: captures)
        #expect(await !runner.hasWork(bundle.folderName), "\(flag) \(state) expects work")
        await runCapture(runner, bundle, capture: captures)

        let started = ContinuousClock.now
        await runner.settle(folderName: bundle.folderName, timeout: .seconds(5))
        #expect(ContinuousClock.now - started < .seconds(1), "\(flag) \(state) waited at round end")

        #expect(await transport.count == 0, "\(flag) \(state) sent a request")
        #expect(await key.reads == 0, "\(flag) \(state) read the key")
        #expect(!bundle.exists("jev.json"), "\(flag) \(state) wrote jev.json")
        #expect(!bundle.exists("refined.md"), "\(flag) \(state) wrote refined.md")
        #expect(!bundle.exists(JevRefinedRenderer.captureFileName(for: bundle.capture)), "\(flag) \(state) wrote a refined file")
        let crops = ItemCrop.fileNames(imageFile: bundle.capture.imageFile, badge: 1)
        #expect(!bundle.exists(crops.annotated) && !bundle.exists(crops.clean))
    }

    @Test("Note coach with every sub-flag off starts nothing, in shadow and on")
    func noteCoachAllSubFlagsOff() async throws {
        for state in [FlagState.shadow, .on] {
            try await expectNothingStarts(NoteCoachJob(), state: state)
        }
    }

    @Test("Crops and search lines with every sub-flag off starts nothing, in shadow and on")
    func cropsAllSubFlagsOff() async throws {
        for state in [FlagState.shadow, .on] {
            try await expectNothingStarts(CropsAnchorsJob(), state: state)
        }
    }

    @Test("Duplicates and conflicts with every sub-flag off starts nothing, in shadow and on")
    func dupesAllSubFlagsOff() async throws {
        // Two captures, so capture 2 has an earlier entry and would send a request.
        for state in [FlagState.shadow, .on] {
            try await expectNothingStarts(DupesConflictsJob(), state: state, captures: 2)
        }
    }

    @Test("An option flag with no parent keeps its own state, and a job never sees its own flag")
    func optionWithoutParent() async throws {
        let bundle = try await Bundle.make()
        let seen = CapSeen()
        let job = CapJob(id: "noteCoach", flag: .noteCoach, options: [.noteCoachVague, .jevSendImages, .noteCoach], seen: seen)
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .noteCoach: .shadow, .noteCoachVague: .on, .jevSendImages: .on]
        await runCapture(makeRunner(bundle, jobs: [job], flags: flags), bundle)

        // jevSendImages has no parent, so the shadow job flag does not cap it.
        #expect(await seen.modes == [.noteCoachVague: .shadow, .jevSendImages: .on])
    }

    @Test("A job with no options gets an empty map, and an unset sub-flag reads as off")
    func defaultsAreEmptyAndOff() async throws {
        #expect(makeContext().optionModes.isEmpty)

        let bundle = try await Bundle.make()
        let seen = CapSeen()
        let plain = TestJob(id: "noteCoach", flag: .noteCoach) { context in
            await seen.record(context.optionModes)
            return .empty
        }
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .noteCoach: .on, .noteCoachVague: .on]
        await runCapture(makeRunner(bundle, jobs: [plain], flags: flags), bundle)
        #expect(plain.options.isEmpty)
        #expect(await seen.modes == [:])

        let second = try await Bundle.make()
        let other = CapSeen()
        let job = CapJob(id: "noteCoach", flag: .noteCoach, options: [.noteCoachVague, .noteCoachQuestion], seen: other)
        await runCapture(makeRunner(second, jobs: [job], flags: [.jevBase: .on, .noteCoach: .on, .noteCoachVague: .on]), second)
        #expect(await other.modes == [.noteCoachVague: .on, .noteCoachQuestion: .off])
    }
}

@Suite("Sub-flags in the gate")
struct SubFlagGateTests {
    /// Each feature job with its flag and sub-flags, from the real registry.
    private static let features: [(job: any JevJob, flag: FeatureFlag, subs: [FeatureFlag])] = [
        (NoteCoachJob(), .noteCoach, FeatureFlag.subFlags(of: .noteCoach)),
        (CropsAnchorsJob(), .cropsAnchors, FeatureFlag.subFlags(of: .cropsAnchors)),
        (DupesConflictsJob(), .dupesConflicts, FeatureFlag.subFlags(of: .dupesConflicts)),
    ]

    private struct Gate: Equatable {
        var mayRun: Bool
        var points: Bool
    }

    private static func gate(_ job: any JevJob, _ states: [FeatureFlag: FlagState]) -> Gate {
        let flags = flagSet(states)
        return Gate(mayRun: JevGate.mayRun(jobs: [job], flags: flags), points: JevGate.pointsToRefinedFiles(jobs: [job], flags: flags))
    }

    @Test("Every feature has sub-flags to test")
    func featuresHaveSubFlags() {
        #expect(Self.features.count == 3)
        for feature in Self.features {
            #expect(!feature.subs.isEmpty, "\(feature.flag)")
        }
    }

    @Test("Each registered job declares exactly the sub-flags of its flag")
    func jobsDeclareTheirSubFlags() throws {
        var checked: [String] = []
        for job in JevJobRegistry.all where !FeatureFlag.subFlags(of: job.flag).isEmpty {
            #expect(Set(job.options) == Set(FeatureFlag.subFlags(of: job.flag)), "\(job.id) misses or adds a sub-flag")
            checked.append(job.id)
        }
        try #require(!checked.isEmpty, "no registered job has sub-flags")
        #expect(checked == ["noteCoach", "cropsAnchors", "dupesConflicts"])

        // Every sub-flag belongs to a feature that has a job.
        for flag in FeatureFlag.allCases {
            if let parent = flag.spec.parent {
                #expect(JevJobRegistry.all.contains { $0.flag == parent }, "\(flag) has a parent with no job")
            }
        }
    }

    @Test("Parent on with every sub-flag off: nothing may run, and no prompt points to a refined file")
    func parentOnSubFlagsOff() {
        for feature in Self.features {
            #expect(Self.gate(feature.job, [.jevBase: .on, feature.flag: .on]) == Gate(mayRun: false, points: false), "\(feature.flag)")
            let off = Dictionary(uniqueKeysWithValues: feature.subs.map { ($0, FlagState.off) })
            #expect(Self.gate(feature.job, off.merging([.jevBase: .on, feature.flag: .on]) { $1 }) == Gate(mayRun: false, points: false), "\(feature.flag)")
        }
    }

    @Test("Parent on with every sub-flag in shadow: the job may run, and no prompt points to a refined file")
    func parentOnSubFlagsShadow() {
        for feature in Self.features {
            let shadow = Dictionary(uniqueKeysWithValues: feature.subs.map { ($0, FlagState.shadow) })
            let states = shadow.merging([.jevBase: .on, feature.flag: .on]) { $1 }
            #expect(Self.gate(feature.job, states) == Gate(mayRun: true, points: false), "\(feature.flag)")
        }
    }

    @Test("Parent in shadow: the sub-flags cap at shadow, so no prompt points to a refined file")
    func parentShadow() {
        for feature in Self.features {
            let on = Dictionary(uniqueKeysWithValues: feature.subs.map { ($0, FlagState.on) })
            let states = on.merging([.jevBase: .on, feature.flag: .shadow]) { $1 }
            #expect(Self.gate(feature.job, states) == Gate(mayRun: true, points: false), "\(feature.flag)")
        }
    }

    @Test("Parent on with one sub-flag on: the job may run, and prompts point to the refined files")
    func oneSubFlagOn() {
        for feature in Self.features {
            for sub in feature.subs {
                #expect(Self.gate(feature.job, [.jevBase: .on, feature.flag: .on, sub: .on]) == Gate(mayRun: true, points: true), "\(feature.flag) with \(sub)")
                // One sub-flag in shadow and none on does not point.
                #expect(Self.gate(feature.job, [.jevBase: .on, feature.flag: .on, sub: .shadow]) == Gate(mayRun: true, points: false), "\(feature.flag) with \(sub) in shadow")
            }
        }
    }

    @Test("A sub-flag alone, or with jevBase off, gates nothing")
    func subFlagAloneOrBaseOff() {
        for feature in Self.features {
            let on = Dictionary(uniqueKeysWithValues: feature.subs.map { ($0, FlagState.on) })
            #expect(Self.gate(feature.job, on.merging([.jevBase: .on]) { $1 }) == Gate(mayRun: false, points: false), "\(feature.flag) parent off")
            #expect(Self.gate(feature.job, on.merging([feature.flag: .on]) { $1 }) == Gate(mayRun: false, points: false), "\(feature.flag) jevBase off")
        }
    }

    @Test("A job with no options keeps the old rule")
    func noOptionsKeepsOldRule() {
        let job = askingJob(.noteCoach)
        #expect(Self.gate(job, [.jevBase: .on, .noteCoach: .on]) == Gate(mayRun: true, points: true))
        #expect(Self.gate(job, [.jevBase: .on, .noteCoach: .shadow]) == Gate(mayRun: true, points: false))
        #expect(Self.gate(job, [.jevBase: .on]) == Gate(mayRun: false, points: false))
    }

    private static func sampleRound() -> FeedbackRound {
        FeedbackRound(name: "feedback", slug: "feedback", folderName: "2026-10-25-1000-feedback", startedAt: Date(timeIntervalSince1970: 1_792_000_000), captures: [sampleCapture()])
    }

    @Test("A copied prompt is unchanged with every sub-flag off or in shadow, and changes with one sub-flag on")
    func copiedPromptFollowsTheGate() {
        let round = Self.sampleRound()
        let capture = sampleCapture()
        let plainRound = PromptBuilder.render(round, folderPath: "/tmp/nextshot-test", refined: false)
        let plainCapture = PromptBuilder.renderCapture(capture, folderPath: "/tmp/nextshot-test", refined: false)

        for feature in Self.features {
            let allOff: [FeatureFlag: FlagState] = [.jevBase: .on, feature.flag: .on]
            let allShadow = Dictionary(uniqueKeysWithValues: feature.subs.map { ($0, FlagState.shadow) }).merging(allOff) { $1 }
            for states in [allOff, allShadow] {
                let points = Self.gate(feature.job, states).points
                #expect(PromptBuilder.render(round, folderPath: "/tmp/nextshot-test", refined: points) == plainRound, "\(feature.flag) \(states)")
                #expect(PromptBuilder.renderCapture(capture, folderPath: "/tmp/nextshot-test", refined: points) == plainCapture, "\(feature.flag) \(states)")
            }

            let oneOn = Self.gate(feature.job, [.jevBase: .on, feature.flag: .on, feature.subs[0]: .on]).points
            #expect(oneOn)
            #expect(PromptBuilder.render(round, folderPath: "/tmp/nextshot-test", refined: oneOn) != plainRound, "\(feature.flag)")
            #expect(PromptBuilder.renderCapture(capture, folderPath: "/tmp/nextshot-test", refined: oneOn) != plainCapture, "\(feature.flag)")
        }
    }

    @Test("With one sub-flag on, the runner expects the capture and settle waits for it")
    func oneSubFlagOnWaits() async throws {
        let bundle = try await Bundle.make()
        let transport = StubTransport(fallback: jsonResponse(noulBody("1.1.names_change")), delay: .seconds(1))
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .noteCoach: .on, .noteCoachVague: .on]
        let runner = makeRunner(bundle, jobs: [NoteCoachJob()], flags: flags, transport: transport)
        await runner.expect(folderName: bundle.folderName, capture: 1)
        #expect(await runner.hasWork(bundle.folderName))

        let started = ContinuousClock.now
        await runner.settle(folderName: bundle.folderName, timeout: .milliseconds(80))
        #expect(ContinuousClock.now - started >= .milliseconds(80))
    }
}
