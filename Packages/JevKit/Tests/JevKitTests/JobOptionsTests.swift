import FeedbackKit
import Foundation
import Testing
@testable import JevKit

/// Holds what a test job saw, across the runner's task boundary.
private actor Seen {
    var modes: [FeatureFlag: FlagState]?

    func record(_ modes: [FeatureFlag: FlagState]) {
        self.modes = modes
    }
}

/// A job with option flags, the shape the data guard uses (#75).
private struct OptionJob: JevJob {
    var id: String
    var flag: FeatureFlag
    var options: [FeatureFlag]
    var version = 1
    let requires: JevDataKinds = []
    let seen: Seen

    func run(_ context: JevJobContext) async throws -> JevJobOutput {
        await seen.record(context.optionModes)
        return .empty
    }
}

@Suite("Job options")
struct JobOptionsTests {
    @Test("A job with no options gets none")
    func defaultIsNone() {
        #expect(NoteCoachJob().options.isEmpty)
        #expect(makeContext().optionModes.isEmpty)
    }

    @Test("An option flag alone starts nothing: no request, no key read, no jev.json")
    func optionAloneRunsNothing() async throws {
        let bundle = try await Bundle.make()
        let transport = StubTransport()
        let key = StubKeyProvider()
        let seen = Seen()
        let job = OptionJob(id: "dataGuard", flag: .dataGuard, options: [.dataGuardContact, .dataGuardFaces], seen: seen)
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .dataGuardContact: .on, .dataGuardFaces: .on, .jevSendImages: .on, .jevSendScreenText: .on]
        let runner = makeRunner(bundle, jobs: [job], flags: flags, transport: transport, key: key)
        await runCapture(runner, bundle)

        #expect(await transport.count == 0)
        #expect(await key.reads == 0)
        #expect(!bundle.exists("jev.json"))
        #expect(await seen.modes == nil)
    }

    @Test("The job gets each option's mode, off for an unset one, and never its own flag")
    func modesReachTheJob() async throws {
        let bundle = try await Bundle.make()
        let seen = Seen()
        let job = OptionJob(id: "dataGuard", flag: .dataGuard, options: [.dataGuardContact, .dataGuardFaces, .dataGuardSecrets, .dataGuard], seen: seen)
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .dataGuard: .shadow, .dataGuardContact: .on, .dataGuardFaces: .shadow]
        let runner = makeRunner(bundle, jobs: [job], flags: flags)
        await runCapture(runner, bundle)

        #expect(await seen.modes == [.dataGuardContact: .on, .dataGuardFaces: .shadow, .dataGuardSecrets: .off])
    }

    @Test("In the runner, a job with no options gets an empty map, even with kind flags on")
    func noOptionsInRunner() async throws {
        let bundle = try await Bundle.make()
        let seen = Seen()
        // TestJob declares no options, so it uses the protocol's default.
        let job = TestJob(id: "noteCoach", flag: .noteCoach) { context in
            await seen.record(context.optionModes)
            return .empty
        }
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .noteCoach: .shadow, .dataGuardContact: .on, .dataGuardFaces: .shadow]
        let runner = makeRunner(bundle, jobs: [job], flags: flags)
        await runCapture(runner, bundle)

        #expect(job.options.isEmpty)
        #expect(await seen.modes == [:])
    }

    @Test("Every kind flag is a dev-only off, shadow, on flag of #70")
    func kindFlags() {
        for flag in [FeatureFlag.dataGuardContact, .dataGuardNumbers, .dataGuardSecrets, .dataGuardFaces] {
            #expect(flag.spec.issue == 70)
            #expect(flag.spec.allowedStates == [.off, .shadow, .on])
            #expect(flag.spec.devOnly)
            #expect(flag.spec.devDefault == .off && flag.spec.releaseDefault == .off)
            #expect(FlagResolver.state(of: flag, channel: .release) { _ in "on" } == .off)
        }
    }
}
