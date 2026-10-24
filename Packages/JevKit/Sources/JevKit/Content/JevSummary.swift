// Packages/JevKit/Sources/JevKit/Content/JevSummary.swift
import Foundation

/// A code-only fact that a job records in jev.json, in shadow and on: for
/// example a final crop box or the index of a chosen OCR line. It can hold
/// numbers, booleans, and code text only, so it never carries reviewer or
/// screen text. A review script reads it without the job's logic.
public indirect enum JevSummaryValue: Equatable, Sendable, Codable, ExpressibleByStringInterpolation, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral {
    case number(Double)
    case bool(Bool)
    case code(JevCodeText)
    case array([JevSummaryValue])
    case object([JevSummaryField])

    public init(stringLiteral value: String) {
        self = .code(JevCodeText(stringLiteral: value))
    }

    public init(stringInterpolation: JevCodeText.StringInterpolation) {
        self = .code(JevCodeText(stringInterpolation: stringInterpolation))
    }

    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }

    public init(floatLiteral value: Double) {
        self = .number(value)
    }

    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    public init(arrayLiteral elements: JevSummaryValue...) {
        self = .array(elements)
    }

    /// Numbers as an array, for example a box: `.numbers([x1, y1, x2, y2])`.
    public static func numbers(_ values: [Int]) -> JevSummaryValue {
        .array(values.map { .number(Double($0)) })
    }

    /// An object with ordered keys: `.fields(["item": "3.1", "box": [10, 20, 30, 40]])`.
    public static func fields(_ pairs: KeyValuePairs<JevCodeText, JevSummaryValue>) -> JevSummaryValue {
        .object(pairs.map { JevSummaryField(key: $0.key, value: $0.value) })
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: Key.self) {
            self = .object(try container.allKeys.sorted { $0.stringValue < $1.stringValue }.map { key in
                JevSummaryField(key: JevCodeText(stringLiteral: key.stringValue), value: try container.decode(JevSummaryValue.self, forKey: key))
            })
            return
        }
        if var container = try? decoder.unkeyedContainer() {
            var items: [JevSummaryValue] = []
            while !container.isAtEnd {
                items.append(try container.decode(JevSummaryValue.self))
            }
            self = .array(items)
            return
        }
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .code(JevCodeText(stringLiteral: try container.decode(String.self)))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .number(let number):
            var container = encoder.singleValueContainer()
            // jev.json must stay valid JSON.
            try container.encode(number.isFinite ? number : 0)
        case .bool(let bool):
            var container = encoder.singleValueContainer()
            try container.encode(bool)
        case .code(let code):
            var container = encoder.singleValueContainer()
            try container.encode(code.text)
        case .array(let items):
            var container = encoder.unkeyedContainer()
            for item in items {
                try container.encode(item)
            }
        case .object(let fields):
            var container = encoder.container(keyedBy: Key.self)
            for field in fields {
                try container.encode(field.value, forKey: Key(stringValue: field.key.text))
            }
        }
    }
}

public struct JevSummaryField: Equatable, Sendable {
    public var key: JevCodeText
    public var value: JevSummaryValue

    public init(key: JevCodeText, value: JevSummaryValue) {
        self.key = key
        self.value = value
    }
}
