// Packages/JevKit/Sources/JevKit/Runner/JevRunner.swift
import FeedbackKit
import Foundation
import Synchronization

/// Limits and budgets for the runner. The defaults come from the Jev design.
public struct JevRunnerSettings: Sendable {
    /// One capture's jobs share this budget, from `start`.
    public var captureBudget: Duration = .seconds(2)
    public var maxConcurrentRequests = 4
    public var maxRequestsPerCapture = 16
    public var maxRequestsPerDay = 1000
    /// This many slow failures in a row (timeout, 5xx, 429, 529) pause
    /// every request for `failurePause`.
    public var failuresBeforePause = 3
    public var failurePause: Duration = .seconds(60)

    public init() {}
}

/// Runs the Jev jobs for each capture, in the background.
///
/// The main actor only starts calls here and never waits for one, except
/// the round-end `settle`, which has its own short timeout. With `jevBase`
/// off, or every job's flag off, nothing is stored, no key is read, and no
/// request is sent.
public actor JevRunner {
    private struct Key: Hashable {
        var folderName: String
        var capture: Int
    }

    private let rootURL: URL
    private let client: JevClient
    private let jobs: [any JevJob]
    private let flags: @Sendable (FeatureFlag) -> FlagState
    private let settings: JevRunnerSettings
    private let log: @Sendable (String) -> Void
    private let now: @Sendable () -> Date
    private let writer: JevBundleWriter
    private let limiter: AsyncLimiter

    /// Captures stored but not started yet. Settle waits for them too.
    private var expected: Set<Key> = []
    private var running: [Key: Task<Void, Never>] = [:]
    /// Every capture started in this app run. The app sends `expect` and
    /// `start` from separate tasks, so an `expect` can arrive after its
    /// `start`. It must not leave the capture expected forever.
    private var started: Set<Key> = []

    private var unauthorized = false
    private var slowFailures = 0
    private var pausedUntil: ContinuousClock.Instant?
    private var requestsByDay: [String: Int] = [:]

    /// - Parameter flags: the resolved state of a flag. It must apply the
    ///   dev-only rule, as `FlagResolver` does.
    /// - Parameter log: receives public text only: job ids, capture numbers,
    ///   statuses, reasons, times, and token counts.
    public init(
        rootURL: URL,
        client: JevClient,
        jobs: [any JevJob] = JevJobRegistry.all,
        flags: @escaping @Sendable (FeatureFlag) -> FlagState,
        settings: JevRunnerSettings = JevRunnerSettings(),
        log: @escaping @Sendable (String) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.rootURL = rootURL
        self.client = client
        self.jobs = jobs
        self.flags = flags
        self.settings = settings
        self.log = log
        self.now = now
        writer = JevBundleWriter(rootURL: rootURL, jobOrder: jobs.map(\.id))
        limiter = AsyncLimiter(limit: settings.maxConcurrentRequests)
    }

    /// Reads the key once, at launch, when Jev may run. The one macOS access
    /// dialog then shows at launch, not in the middle of a capture.
    public func warmUp() async {
        guard JevGate.mayRun(jobs: jobs, flags: flags) else { return }
        _ = await client.hasKey()
    }

    /// A capture was stored. Settle waits for it. Sends nothing.
    public func expect(folderName: String, capture: Int) {
        let key = Key(folderName: folderName, capture: capture)
        guard !started.contains(key), JevGate.mayRun(jobs: jobs, flags: flags) else { return }
        expected.insert(key)
    }

    /// The capture's notes are final and its screen text is stored. Starts
    /// its jobs and returns at once. A capture runs once per app run.
    /// `screenLines` are the OCR lines with boxes that the app holds in
    /// memory; feedback.json keeps only their joined text.
    public func start(folderName: String, capture: Int, screenLines: [FeedbackTextLine]? = nil) {
        let key = Key(folderName: folderName, capture: capture)
        guard started.insert(key).inserted else { return }

        // Flags are read once, so a change during a capture has effect at
        // the next one.
        let states = Dictionary(uniqueKeysWithValues: FeatureFlag.allCases.map { ($0, flags($0)) })
        let state: @Sendable (FeatureFlag) -> FlagState = { states[$0] ?? .off }
        guard JevGate.mayRun(jobs: jobs, flags: state) else {
            expected.remove(key)
            return
        }
        let planned = jobs.compactMap { job -> (job: any JevJob, mode: FlagState)? in
            let mode = state(job.flag)
            return mode == .off ? nil : (job, mode)
        }
        let allowed = JevGate.allowedKinds(flags: state)
        let lines = screenLines?.compactMap { line in
            ScreenText.field(line.text).map { FeedbackTextLine(text: $0, box: line.box) }
        }

        running[key] = Task {
            await self.run(key: key, planned: planned, allowed: allowed, screenLines: lines)
            self.finish(key)
        }
    }

    /// Waits at most `timeout` for the round's expected and running
    /// captures, then writes refined.md with any capture still running
    /// marked. Returns at once when the round has none.
    public func settle(folderName: String, timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        while hasWork(folderName), ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                // A cancelled caller would make the sleep return at once.
                break
            }
        }
        let left = Set(expected.filter { $0.folderName == folderName }.map(\.capture))
            .union(running.keys.filter { $0.folderName == folderName }.map(\.capture))
        if !left.isEmpty {
            log("settle: \(left.count) captures still running at round end")
        }
        guard JevGate.pointsToRefinedFiles(jobs: jobs, flags: flags) else { return }
        do {
            try await writer.settle(folderName: folderName, running: left)
        } catch {
            log("settle: refined.md not written")
        }
    }

    /// True while the folder has a capture expected or running. For tests.
    func hasWork(_ folderName: String) -> Bool {
        expected.contains { $0.folderName == folderName } || running.keys.contains { $0.folderName == folderName }
    }

    private func finish(_ key: Key) {
        running[key] = nil
        expected.remove(key)
    }

    // MARK: - One capture

    private func run(key: Key, planned: [(job: any JevJob, mode: FlagState)], allowed: JevDataKinds, screenLines: [FeedbackTextLine]?) async {
        let startedAt = now()
        var finished: [JevBundleWriter.Finished] = []
        var runnable: [(job: any JevJob, mode: FlagState)] = []

        // Jobs that cannot run are recorded first, and need no key.
        for entry in planned {
            if entry.job.requires.isSubset(of: allowed) {
                runnable.append(entry)
            } else {
                finished.append(.init(record: Self.skipped(entry.job, mode: entry.mode, reason: .consent, at: startedAt), output: nil))
            }
        }
        if let reason = pauseReason() {
            finished += runnable.map { .init(record: Self.skipped($0.job, mode: $0.mode, reason: reason, at: startedAt), output: nil) }
            runnable = []
        } else if !runnable.isEmpty, !(await client.hasKey()) {
            finished += runnable.map { .init(record: Self.skipped($0.job, mode: $0.mode, reason: .noKey, at: startedAt), output: nil) }
            runnable = []
        }

        guard let round = FeedbackLibrary.round(named: key.folderName, in: rootURL),
              let capture = round.captures.first(where: { $0.index == key.capture })
        else {
            log("capture \(key.capture): not found in feedback.json, nothing recorded")
            return
        }

        let folderURL = rootURL.appendingPathComponent(key.folderName, isDirectory: true)
        let deadline = ContinuousClock.now + settings.captureBudget
        let budget = RequestBudget(limit: settings.maxRequestsPerCapture)
        let images = JevImageLoader.bundle(folderURL: folderURL, round: round)

        await withTaskGroup(of: JevBundleWriter.Finished.self) { group in
            for entry in runnable {
                group.addTask {
                    await self.runJob(entry.job, mode: entry.mode, round: round, capture: capture, folderURL: folderURL,
                                      allowed: allowed, deadline: deadline, budget: budget, images: images,
                                      screenLines: screenLines, startedAt: startedAt)
                }
            }
            for await result in group {
                finished.append(result)
            }
        }

        for result in finished {
            let record = result.record
            // Check names and question ids are code constants, so they are public.
            let check = record.failedCheck.map { " [\($0)]" } ?? ""
            let dropped = record.dropped.map { ", dropped \($0.joined(separator: "; "))" } ?? ""
            log("capture \(key.capture) \(record.job): \(record.status.rawValue)\(record.reason.map { " (\($0.rawValue))" } ?? "")\(check), \(record.requests) requests, \(record.durationMs) ms, \(record.inputTokens) input tokens\(dropped)")
        }
        do {
            try await writer.record(folderName: key.folderName, round: round, capture: capture, jobs: finished)
        } catch {
            log("capture \(key.capture): jev.json not written")
        }
    }

    private func runJob(
        _ job: any JevJob,
        mode: FlagState,
        round: FeedbackRound,
        capture: FeedbackCapture,
        folderURL: URL,
        allowed: JevDataKinds,
        deadline: ContinuousClock.Instant,
        budget: RequestBudget,
        images: JevImageLoader,
        screenLines: [FeedbackTextLine]?,
        startedAt: Date
    ) async -> JevBundleWriter.Finished {
        let clockStart = ContinuousClock.now
        let recorder = AnswerRecorder()
        let asker = JevAsker { request in
            try await self.send(request, allowed: allowed, deadline: deadline, budget: budget, recorder: recorder)
        }
        let context = JevJobContext(round: round, capture: capture, folderURL: folderURL, allowed: allowed,
                                    deadline: deadline, jev: asker, images: images, screenLines: screenLines)

        let outcome = await Self.race(deadline: deadline) {
            do {
                return .success(try await job.run(context))
            } catch let error as JevError {
                return .failure(error)
            } catch is CancellationError {
                return .failure(JevError(.timeout))
            } catch {
                return .failure(JevError(.jobError))
            }
        }

        let elapsed = ContinuousClock.now - clockStart
        let stats = await recorder.snapshot()
        var record = JevJobRecord(
            job: job.id,
            jobVersion: job.version,
            mode: mode.rawValue,
            status: .done,
            reason: nil,
            model: JevEndpoint.model,
            startedAt: startedAt,
            durationMs: Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000),
            requests: stats.requests,
            retries: stats.retries,
            inputTokens: stats.inputTokens,
            requestIDs: stats.requestIDs,
            answers: stats.answers,
            lines: [],
            files: [],
            dropped: stats.dropped.isEmpty ? nil : stats.dropped
        )
        switch outcome {
        case .success(let output):
            // Summary and review go to jev.json in shadow and on. Lines and
            // files go to the bundle in on only.
            record.summary = output.summary.isEmpty ? nil : .object(output.summary)
            record.review = output.review
            if let failure = output.failure {
                record.status = .notRefined
                record.reason = failure.reason
            }
            return .init(record: record, output: mode == .on ? output : nil)
        case .failure(let error):
            record.status = .notRefined
            record.reason = error.reason
            record.failedCheck = error.check
            return .init(record: record, output: nil)
        }
    }

    /// The job's result, or a timeout at the deadline, whichever comes first.
    /// At the deadline the job's task is cancelled, which also cancels its
    /// open request. The caller never waits for a job that ignores
    /// cancellation: its late result is dropped.
    static func race(
        deadline: ContinuousClock.Instant,
        _ work: @escaping @Sendable () async -> Result<JevJobOutput, JevError>
    ) async -> Result<JevJobOutput, JevError> {
        let gate = OnceGate()
        return await withCheckedContinuation { continuation in
            let job = Task {
                let result = await work()
                if gate.claim() {
                    continuation.resume(returning: result)
                }
            }
            Task {
                try? await Task.sleep(until: deadline, clock: .continuous)
                if gate.claim() {
                    job.cancel()
                    continuation.resume(returning: .failure(JevError(.timeout)))
                }
            }
        }
    }

    // MARK: - One request

    /// The asker's send: consent, pauses, caps, and the concurrency limit,
    /// then the client. Every answer goes to the recorder.
    private func send(_ request: JevRequest, allowed: JevDataKinds, deadline: ContinuousClock.Instant, budget: RequestBudget, recorder: AnswerRecorder) async throws -> JevResponse {
        // Consent sits under every job: a job bug cannot send data without it.
        guard request.kinds.isSubset(of: allowed) else { throw JevError(.consent) }
        if let reason = pauseReason() { throw JevError(reason) }

        do {
            try await limiter.acquire()
        } catch {
            throw JevError(.timeout)
        }
        do {
            // Checked again before each HTTP attempt, after the wait for a
            // slot: a pause that began meanwhile stops this request, and
            // retries count toward the caps.
            let result = try await client.send(request, deadline: deadline) {
                try await self.admitAttempt(budget: budget)
            }
            await limiter.release()
            noteSuccess()
            await recorder.add(result, questionOrder: request.questions.map(\.id.text))
            return result.response
        } catch let error as JevError {
            await limiter.release()
            noteFailure(error)
            await recorder.addFailure()
            throw error
        } catch {
            await limiter.release()
            throw JevError(.offline)
        }
    }

    /// One HTTP attempt may go out: no pause, and room under both caps.
    private func admitAttempt(budget: RequestBudget) async throws {
        if let reason = pauseReason() { throw JevError(reason) }
        guard await budget.take() else { throw JevError(.capReached) }
        guard takeDailyRequest() else { throw JevError(.capReached) }
    }

    private func pauseReason() -> JevFailureReason? {
        if unauthorized { return .paused }
        if let pausedUntil, ContinuousClock.now < pausedUntil { return .paused }
        return nil
    }

    private func takeDailyRequest() -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: now())
        let count = requestsByDay[day, default: 0]
        guard count < settings.maxRequestsPerDay else { return false }
        requestsByDay = [day: count + 1]
        return true
    }

    private func noteSuccess() {
        slowFailures = 0
    }

    private func noteFailure(_ error: JevError) {
        switch error.reason {
        case .unauthorized where error.status == 401:
            if !unauthorized {
                log("TypeSafe rejected the key (HTTP 401). Jev requests pause until the next launch.")
            }
            unauthorized = true
        case .unauthorized, .timeout, .server, .rateLimited, .overloaded:
            // A 403 can be a proxy's block page (Cisco Umbrella on m4max),
            // not a bad key, so it counts as a slow failure instead.
            slowFailures += 1
            if slowFailures >= settings.failuresBeforePause {
                slowFailures = 0
                pausedUntil = ContinuousClock.now + settings.failurePause
                log("\(settings.failuresBeforePause) slow failures in a row: Jev requests pause for \(settings.failurePause)")
            }
        default:
            break
        }
    }

    private static func skipped(_ job: any JevJob, mode: FlagState, reason: JevFailureReason, at date: Date) -> JevJobRecord {
        JevJobRecord(
            job: job.id, jobVersion: job.version, mode: mode.rawValue, status: .skipped, reason: reason,
            model: JevEndpoint.model, startedAt: date, durationMs: 0, requests: 0, retries: 0, inputTokens: 0,
            requestIDs: [], answers: [], lines: [], files: []
        )
    }
}

/// Lets exactly one of several callers win, so a continuation resumes once.
final class OnceGate: Sendable {
    private let claimed = Mutex(false)

    func claim() -> Bool {
        claimed.withLock { claimed in
            if claimed { return false }
            claimed = true
            return true
        }
    }
}

/// The per-capture request cap, shared by the capture's jobs. It counts
/// HTTP attempts, so retries count too.
actor RequestBudget {
    private var left: Int

    init(limit: Int) {
        left = limit
    }

    func take() -> Bool {
        guard left > 0 else { return false }
        left -= 1
        return true
    }
}

/// Collects what jev.json records about one job's requests.
actor AnswerRecorder {
    struct Snapshot: Sendable {
        var requests = 0
        var retries = 0
        var inputTokens = 0
        var requestIDs: [String] = []
        var answers: [JevAnswerRecord] = []
        var dropped: [String] = []
    }

    private var current = Snapshot()

    func add(_ result: JevSendResult, questionOrder: [String]) {
        current.requests += 1
        current.retries += result.retries
        // Each count is at most 10 million (the decoder checks it) and a job
        // makes at most 16 attempts, so the sum cannot overflow.
        current.inputTokens += result.response.inputTokens
        if let id = result.response.requestID {
            current.requestIDs.append(id)
        }
        for id in questionOrder {
            if let answer = result.response.answers[id] {
                current.answers.append(JevAnswerRecord(id: id, answer: answer))
            } else if let check = result.response.dropped[id] {
                current.dropped.append("\(id): \(check)")
            }
        }
    }

    func addFailure() {
        current.requests += 1
    }

    func snapshot() -> Snapshot {
        current
    }
}
