// Packages/JevKit/Sources/JevKit/Jobs/JevJob.swift
import FeedbackKit
import Foundation

/// One feature's work for one capture. Each feature supplies one type that
/// follows this protocol, in its own file, and one line in `JevJobRegistry`.
///
/// Rules (docs/superpowers/specs/2026-10-24-jev-base-design.md, "The job
/// interface"):
/// - Ask Jev only through `context.jev`. Never build a URL or a session.
/// - Never write a file. Return files in the output.
/// - Never decide by flag state. Shadow and on run the same questions.
/// - Never read another job's output.
/// - A label may add, group, or order. It never hides or changes Drew's words.
public protocol JevJob: Sendable {
    /// Stable name, used in jev.json, logs, and file names. Never rename a
    /// job that has run.
    var id: String { get }
    /// The flag that runs this job. `jevBase` must be on too.
    var flag: FeatureFlag { get }
    /// Data kinds the job cannot work without. The runner skips the job when
    /// one has no consent. Reviewer text needs no extra consent.
    var requires: JevDataKinds { get }
    /// Raise it when the questions change, so old and new answers are never
    /// mixed in a comparison.
    var version: Int { get }
    /// One capture's work. Throwing records "jobError" for this job only.
    func run(_ context: JevJobContext) async throws -> JevJobOutput
}

/// Sends one request for a job. The runner supplies it. It refuses a request
/// with a data kind outside `allowed`, stops at the request cap and the
/// deadline, and records every answer in jev.json.
public struct JevAsker: Sendable {
    private let send: @Sendable (JevRequest) async throws -> JevResponse

    public init(_ send: @escaping @Sendable (JevRequest) async throws -> JevResponse) {
        self.send = send
    }

    /// Throws `JevError` on any failure. A job can catch it and try a
    /// smaller request, or let it end the job.
    public func ask(_ request: JevRequest) async throws -> JevResponse {
        try await send(request)
    }
}

/// Loads a capture's PNG from the bundle, or a region of it, sized for Jev.
/// The runner supplies one that reads the bundle folder.
public struct JevImageLoader: Sendable {
    public enum Variant: Sendable {
        /// The PNG with Drew's marks and numbered badges.
        case annotated
        /// The PNG without marks. Redact marks stay applied.
        case clean
    }

    private let load: @Sendable (_ capture: Int, _ variant: Variant, _ region: FeedbackBox?) throws -> JevImage

    public init(_ load: @escaping @Sendable (_ capture: Int, _ variant: Variant, _ region: FeedbackBox?) throws -> JevImage) {
        self.load = load
    }

    /// `region` is in the capture's pixels. Nil means the whole image.
    public func image(of capture: Int, _ variant: Variant = .annotated, region: FeedbackBox? = nil) throws -> JevImage {
        try load(capture, variant, region)
    }
}

/// What a job gets for one capture.
public struct JevJobContext: Sendable {
    /// Read from feedback.json when the job starts. It holds the final notes
    /// and screen text, and every earlier capture of the round.
    public let round: FeedbackRound
    /// The capture to refine.
    public let capture: FeedbackCapture
    public let folderURL: URL
    /// Kinds with consent for this run. Always holds `.reviewerText`.
    public let allowed: JevDataKinds
    /// The capture's deadline. The asker stops here too.
    public let deadline: ContinuousClock.Instant
    public let jev: JevAsker
    public let images: JevImageLoader
    /// The capture's OCR lines with their boxes, in the capture's pixels,
    /// with redacted lines removed and each text cleaned. feedback.json keeps
    /// only the joined text, so this comes from memory: nil when unknown, for
    /// example when the editor changed the capture's size. Screen text: send
    /// it only as `.screen`.
    public let screenLines: [FeedbackTextLine]?

    public init(
        round: FeedbackRound,
        capture: FeedbackCapture,
        folderURL: URL,
        allowed: JevDataKinds,
        deadline: ContinuousClock.Instant,
        jev: JevAsker,
        images: JevImageLoader,
        screenLines: [FeedbackTextLine]? = nil
    ) {
        self.round = round
        self.capture = capture
        self.folderURL = folderURL
        self.allowed = allowed
        self.deadline = deadline
        self.jev = jev
        self.images = images
        self.screenLines = screenLines
    }
}

/// One line for the refined files. The writer renders it as
/// `- <label> "<screen text>" `<absolute file path>``, with each part only
/// when present.
public struct JevRefinedLine: Equatable, Sendable {
    public enum Scope: Equatable, Sendable {
        /// The round section at the top of refined.md, for example a conflict
        /// between two items.
        case round
        /// The capture as a whole.
        case capture
        /// One numbered badge of the capture: item K.N.
        case item(badge: Int)
    }

    public var scope: Scope
    /// Written by code, so screen text can reach a refined file only in
    /// quotes, through `screenText`. One line: the writer joins line breaks.
    public var label: JevCodeText
    /// Screen text to show after the label, in quotes, marked as screen text.
    public var screenText: String?
    /// A file name from the output's `files`. Shown as an absolute path.
    public var file: String?

    public init(scope: Scope, label: JevCodeText, screenText: String? = nil, file: String? = nil) {
        self.scope = scope
        self.label = label
        self.screenText = screenText
        self.file = file
    }
}

/// An extra file for the bundle, for example an item crop. The name must
/// start with the capture's file stem and a hyphen, use only `a-z`, `0-9`,
/// `-`, and `.`, end in `.png` or `.md`, and name no file of any capture in
/// the round.
public struct JevRefinedFile: Equatable, Sendable {
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

/// What a job returns. Answers need no field here: the runner records every
/// answer itself.
///
/// | Field | Written in | Where |
/// | --- | --- | --- |
/// | `lines`, `files` | on only | the refined files and the bundle |
/// | `summary` | shadow and on | the job's record in jev.json |
/// | `review` | shadow and on | `jev-review/<job id>.md`, for Drew only |
public struct JevJobOutput: Equatable, Sendable {
    public var lines: [JevRefinedLine]
    public var files: [JevRefinedFile]
    /// Code-only facts for a review script, for example a final crop box.
    public var summary: [JevSummaryField]
    /// This capture's section of the job's review file, in Markdown. No
    /// prompt names the file, and its first line tells agents not to act on
    /// it. It may hold reviewer text and numbers. Keep screen text out.
    public var review: String?
    /// A Jev failure that the job handled. The record says "not refined"
    /// with this reason, and the rest of the output is still written.
    public var failure: JevError?

    public init(
        lines: [JevRefinedLine] = [],
        files: [JevRefinedFile] = [],
        summary: [JevSummaryField] = [],
        review: String? = nil,
        failure: JevError? = nil
    ) {
        self.lines = lines
        self.files = files
        self.summary = summary
        self.review = review
        self.failure = failure
    }

    public static let empty = JevJobOutput()
}
