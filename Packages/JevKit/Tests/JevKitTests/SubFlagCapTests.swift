import FeedbackKit
import Foundation
import Testing
@testable import JevKit

// The runner reads a sub-flag at the lower of its own state and its parent's
// (#94). These tests run the real runner on a real round on disk.

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
    @Test("A sub-flag reaches the job at the lower of its state and the job flag's, for all nine pairs")
    func capForAllNinePairs() async throws {
        var ran = 0
        for parent in order {
            for sub in order {
                let bundle = try await Bundle.make()
                let seen = CapSeen()
                let job = CapJob(id: "noteCoach", flag: .noteCoach, options: [.noteCoachVague], seen: seen)
                let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .noteCoach: parent, .noteCoachVague: sub]
                await runCapture(makeRunner(bundle, jobs: [job], flags: flags), bundle)

                if parent == .off {
                    // The job flag is off, so the job does not run at all.
                    #expect(await seen.modes == nil, "parent off, sub \(sub)")
                } else {
                    #expect(await seen.modes == [.noteCoachVague: lower(sub, parent)], "parent \(parent), sub \(sub)")
                    ran += 1
                }
            }
        }
        #expect(ran == 6, "the loop skipped a pair")
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

    /// Runs `job` with its feature flag at `state`, every consent on, and no
    /// sub-flag set. The job must run, send no request, and write nothing.
    private func expectNoRequest(_ job: any JevJob, state: FlagState) async throws {
        let flag = job.flag
        let bundle = try await Bundle.make()
        let transport = StubTransport(fallback: jsonResponse(noulBody("1.1.names_change")))
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, flag: state, .jevSendImages: .on, .jevSendScreenText: .on]
        await runCapture(makeRunner(bundle, jobs: [job], flags: flags, transport: transport), bundle)

        #expect(await transport.count == 0, "\(flag) \(state) sent a request")
        // The job still ran: its record says done, with no request and no output.
        let record = try #require(try bundle.record(1), "\(flag) \(state) wrote no record")
        #expect(record.job == flag.rawValue && record.status == .done)
        #expect(record.requests == 0 && record.answers.isEmpty && record.lines.isEmpty && record.files.isEmpty)
        #expect(record.summary == nil && record.review == nil)
        #expect(!bundle.exists(JevRefinedRenderer.captureFileName(for: bundle.capture)), "\(flag) \(state) wrote a refined file")
        let crops = ItemCrop.fileNames(imageFile: bundle.capture.imageFile, badge: 1)
        #expect(!bundle.exists(crops.annotated) && !bundle.exists(crops.clean))
    }

    @Test("Note coach with every sub-flag off runs but sends no request, in shadow and on")
    func noteCoachAllSubFlagsOff() async throws {
        for state in [FlagState.shadow, .on] {
            try await expectNoRequest(NoteCoachJob(), state: state)
        }
    }

    @Test("Crops and search lines with every sub-flag off runs but sends no request, in shadow and on")
    func cropsAllSubFlagsOff() async throws {
        for state in [FlagState.shadow, .on] {
            try await expectNoRequest(CropsAnchorsJob(), state: state)
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
