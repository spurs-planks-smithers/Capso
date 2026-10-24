// Packages/JevKit/Sources/JevKit/Content/JevAnswer.swift
import Foundation

/// A box as fractions of the sent image, origin top-left. The client checks
/// that each edge is from 0 to 1, `top` < `bottom`, and `left` < `right`.
public struct JevBox: Codable, Equatable, Sendable {
    public var top: Double
    public var bottom: Double
    public var left: Double
    public var right: Double

    public init(top: Double, bottom: Double, left: Double, right: Double) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }
}

public struct JevChoiceAnswer: Codable, Equatable, Sendable {
    /// One of the option names that the question sent.
    public var option: String
    public var confidence: Double
    /// One entry per option sent, each from 0 to 1.
    public var probabilities: [String: Double]

    public init(option: String, confidence: Double, probabilities: [String: Double]) {
        self.option = option
        self.confidence = confidence
        self.probabilities = probabilities
    }
}

public struct JevScoreAnswer: Codable, Equatable, Sendable {
    /// The expected level, from 0 to the top level. It can fall between levels.
    public var score: Double
    public var confidence: Double
    /// Entry N is the probability of level N.
    public var probabilities: [Double]

    public init(score: Double, confidence: Double, probabilities: [Double]) {
        self.score = score
        self.confidence = confidence
        self.probabilities = probabilities
    }
}

public struct JevBoxAnswer: Codable, Equatable, Sendable {
    public var box: JevBox
    /// Nil when the model gives none.
    public var confidence: Double?

    public init(box: JevBox, confidence: Double?) {
        self.box = box
        self.confidence = confidence
    }
}

/// One checked answer. Its type always matches its question's type.
public enum JevAnswer: Equatable, Sendable {
    /// The probability of yes, from 0 to 1. Near 0.5 means unsure.
    case noul(Double)
    case choice(JevChoiceAnswer)
    case score(JevScoreAnswer)
    case box(JevBoxAnswer)
}

/// A checked response. Every question sent has exactly one answer here.
public struct JevResponse: Equatable, Sendable {
    /// The model that answered. The client accepts only the pinned model.
    public var model: String
    public var answers: [String: JevAnswer]
    public var inputTokens: Int
    public var outputTokens: Int
    /// TypeSafe's `x-typesafe-request-id`, for a support question.
    public var requestID: String?

    public init(model: String, answers: [String: JevAnswer], inputTokens: Int, outputTokens: Int, requestID: String? = nil) {
        self.model = model
        self.answers = answers
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requestID = requestID
    }

    public func noul(_ id: String) -> Double? {
        if case .noul(let probability) = answers[id] { return probability }
        return nil
    }

    public func choice(_ id: String) -> JevChoiceAnswer? {
        if case .choice(let answer) = answers[id] { return answer }
        return nil
    }

    public func score(_ id: String) -> JevScoreAnswer? {
        if case .score(let answer) = answers[id] { return answer }
        return nil
    }

    public func box(_ id: String) -> JevBoxAnswer? {
        if case .box(let answer) = answers[id] { return answer }
        return nil
    }
}
