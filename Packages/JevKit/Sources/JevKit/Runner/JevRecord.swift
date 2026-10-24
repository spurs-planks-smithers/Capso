// Packages/JevKit/Sources/JevKit/Runner/JevRecord.swift
import Foundation

/// `jev.json`: one per bundle. It is the source of truth for Jev results, as
/// `feedback.json` is for the round. The refined files are rendered from it.
public struct JevRecordFile: Codable, Equatable, Sendable {
    public static let fileName = "jev.json"
    public static let currentSchemaVersion = 1
    public static let aboutText = "Answers from Jev (TypeSafe), a typed-judgment model. The reviewer's words in feedback.json win over every answer here."

    public var schemaVersion: Int
    public var about: String
    public var captures: [JevCaptureRecord]

    public init(captures: [JevCaptureRecord] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.about = Self.aboutText
        self.captures = captures
    }
}

public struct JevCaptureRecord: Codable, Equatable, Sendable {
    public var capture: Int
    public var jobs: [JevJobRecord]

    public init(capture: Int, jobs: [JevJobRecord]) {
        self.capture = capture
        self.jobs = jobs
    }
}

/// One job's run on one capture.
public struct JevJobRecord: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// The job ran and returned.
        case done
        /// The job ran and failed. `reason` says why.
        case notRefined
        /// The job did not run. `reason` says why.
        case skipped
    }

    public var job: String
    public var jobVersion: Int
    /// "shadow" or "on".
    public var mode: String
    public var status: Status
    public var reason: JevFailureReason?
    public var model: String
    public var startedAt: Date
    public var durationMs: Int
    public var requests: Int
    public var retries: Int
    public var inputTokens: Int
    public var requestIDs: [String]
    /// Every answer of every request the job sent, in order.
    public var answers: [JevAnswerRecord]
    /// On mode only: the lines the refined files show. Empty in shadow.
    public var lines: [JevLineRecord]
    /// On mode only: the extra files written to the bundle. Empty in shadow.
    public var files: [String]

    public var isOn: Bool { mode == "on" }
}

/// One answer, as stored. The `probabilities` key holds a map for a Choice
/// and a list (level 0 first) for a Score.
public struct JevAnswerRecord: Codable, Equatable, Sendable {
    public var id: String
    public var answer: JevAnswer

    public init(id: String, answer: JevAnswer) {
        self.id = id
        self.answer = answer
    }

    private enum Keys: String, CodingKey {
        case id, type, noul, choice, score, box, confidence, probabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        id = try container.decode(String.self, forKey: .id)
        switch try container.decode(String.self, forKey: .type) {
        case "noul":
            answer = .noul(try container.decode(Double.self, forKey: .noul))
        case "choice":
            answer = .choice(JevChoiceAnswer(
                option: try container.decode(String.self, forKey: .choice),
                confidence: try container.decode(Double.self, forKey: .confidence),
                probabilities: try container.decode([String: Double].self, forKey: .probabilities)
            ))
        case "score":
            answer = .score(JevScoreAnswer(
                score: try container.decode(Double.self, forKey: .score),
                confidence: try container.decode(Double.self, forKey: .confidence),
                probabilities: try container.decode([Double].self, forKey: .probabilities)
            ))
        case "box":
            answer = .box(JevBoxAnswer(
                box: try container.decode(JevBox.self, forKey: .box),
                confidence: try container.decodeIfPresent(Double.self, forKey: .confidence)
            ))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "unknown answer type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(id, forKey: .id)
        switch answer {
        case .noul(let probability):
            try container.encode("noul", forKey: .type)
            try container.encode(probability, forKey: .noul)
        case .choice(let choice):
            try container.encode("choice", forKey: .type)
            try container.encode(choice.option, forKey: .choice)
            try container.encode(choice.confidence, forKey: .confidence)
            try container.encode(choice.probabilities, forKey: .probabilities)
        case .score(let score):
            try container.encode("score", forKey: .type)
            try container.encode(score.score, forKey: .score)
            try container.encode(score.confidence, forKey: .confidence)
            try container.encode(score.probabilities, forKey: .probabilities)
        case .box(let box):
            try container.encode("box", forKey: .type)
            try container.encode(box.box, forKey: .box)
            try container.encode(box.confidence, forKey: .confidence)
        }
    }
}

/// A refined line as stored: `scope` is "round", "capture", or "item", and
/// `badge` is set for an item.
public struct JevLineRecord: Codable, Equatable, Sendable {
    public var scope: String
    public var badge: Int?
    public var label: String
    public var screenText: String?
    public var file: String?

    init(_ line: JevRefinedLine) {
        switch line.scope {
        case .round: scope = "round"
        case .capture: scope = "capture"
        case .item(let badge):
            scope = "item"
            self.badge = badge
        }
        label = line.label
        screenText = line.screenText
        file = line.file
    }
}
