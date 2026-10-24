// Packages/JevKit/Sources/JevKit/Content/JevQuestion.swift
import Foundation

/// One typed question. TypeSafe's primitives pages describe each type:
/// docs.typesafe.ai/primitives.
public struct JevQuestion: Sendable {
    public enum Kind: Sendable {
        /// Yes or no. The answer is the probability of yes. `yes` and `no`
        /// are optional criteria for what counts as each answer.
        case noul(yes: JevValue?, no: JevValue?)
        /// One option of a set. Option names are code and come back in the answer.
        case choice(options: [(name: JevCodeText, description: JevValue)])
        /// Ordered levels, lowest first. The answer is a level number.
        case score(levels: [JevValue])
        /// Where something is in an image. Needs an image in the request.
        /// A Box always returns a box: ask a Noul next to it for "is it there?".
        case box
    }

    public var instructions: JevValue
    public var kind: Kind

    public init(instructions: JevValue, kind: Kind) {
        self.instructions = instructions
        self.kind = kind
    }

    public static func noul(_ instructions: JevValue, yes: JevValue? = nil, no: JevValue? = nil) -> JevQuestion {
        JevQuestion(instructions: instructions, kind: .noul(yes: yes, no: no))
    }

    public static func choice(_ instructions: JevValue, options: KeyValuePairs<JevCodeText, JevValue>) -> JevQuestion {
        JevQuestion(instructions: instructions, kind: .choice(options: options.map { (name: $0.key, description: $0.value) }))
    }

    public static func score(_ instructions: JevValue, levels: [JevValue]) -> JevQuestion {
        JevQuestion(instructions: instructions, kind: .score(levels: levels))
    }

    public static func box(_ instructions: JevValue) -> JevQuestion {
        JevQuestion(instructions: instructions, kind: .box)
    }

    /// The kinds the question's own text holds.
    public var kinds: JevDataKinds {
        var kinds = instructions.kinds
        switch kind {
        case .noul(let yes, let no):
            kinds.formUnion(yes?.kinds ?? [])
            kinds.formUnion(no?.kinds ?? [])
        case .choice(let options):
            for option in options {
                kinds.formUnion(option.description.kinds)
            }
        case .score(let levels):
            for level in levels {
                kinds.formUnion(level.kinds)
            }
        case .box:
            break
        }
        return kinds
    }

    /// The values inside the question, for finding images.
    var values: [JevValue] {
        var values = [instructions]
        switch kind {
        case .noul(let yes, let no):
            values += [yes, no].compactMap { $0 }
        case .choice(let options):
            values += options.map(\.description)
        case .score(let levels):
            values += levels
        case .box:
            break
        }
        return values
    }
}

/// One request: a state and named questions. All questions see the same
/// state and run in parallel, so they cannot see each other's answers.
public struct JevRequest: Sendable {
    public var state: JevValue
    /// In order. IDs are for code only: TypeSafe does not send them to the model.
    public var questions: [(id: JevCodeText, question: JevQuestion)]

    public init(state: JevValue, questions: [(id: JevCodeText, question: JevQuestion)]) {
        self.state = state
        self.questions = questions
    }

    public init(state: JevValue, questions: KeyValuePairs<JevCodeText, JevQuestion>) {
        self.init(state: state, questions: questions.map { (id: $0.key, question: $0.value) })
    }

    /// Every data kind in the request. The sender checks it against consent.
    public var kinds: JevDataKinds {
        questions.reduce(state.kinds) { $0.union($1.question.kinds) }
    }

    /// Every distinct image in the request, state first.
    public var images: [JevImage] {
        var seen = Set<UUID>()
        var found: [JevImage] = []
        state.collectImages(into: &found, seen: &seen)
        for entry in questions {
            for value in entry.question.values {
                value.collectImages(into: &found, seen: &seen)
            }
        }
        return found
    }

    /// True when TypeSafe needs the images header: an image or a Box question.
    public var needsImagesHeader: Bool {
        !images.isEmpty || questions.contains { entry in
            if case .box = entry.question.kind { return true }
            return false
        }
    }
}
