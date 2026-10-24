// Packages/JevKit/Sources/JevKit/Content/JevCodeText.swift
import Foundation

/// Text that a job's own code writes: question wording, field keys, option
/// names, and question ids. It needs no consent, so it must never hold
/// reviewer or screen text.
///
/// The compiler enforces that. A `JevCodeText` comes only from a string
/// literal, and an interpolation inside it accepts only numbers and other
/// code text. `"Item \(index)"` compiles. `"Search \(ocrLine)"` with a
/// `String` does not: mark that text `.screen` or `.reviewer` instead.
public struct JevCodeText: Hashable, Sendable, ExpressibleByStringInterpolation, CustomStringConvertible {
    public let text: String

    public init(stringLiteral value: String) {
        text = value
    }

    public init(stringInterpolation: StringInterpolation) {
        text = stringInterpolation.text
    }

    public var description: String { text }

    public struct StringInterpolation: StringInterpolationProtocol {
        var text = ""

        public init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity)
        }

        public mutating func appendLiteral(_ literal: String) {
            text += literal
        }

        public mutating func appendInterpolation(_ value: Int) {
            text += String(value)
        }

        public mutating func appendInterpolation(_ value: Double) {
            text += String(value)
        }

        public mutating func appendInterpolation(_ value: JevCodeText) {
            text += value.text
        }
    }

    /// Code texts joined by a code-text separator, for example a list of
    /// item ids.
    public static func joined(_ parts: [JevCodeText], separator: JevCodeText = ", ") -> JevCodeText {
        var interpolation = StringInterpolation(literalCapacity: 0, interpolationCount: 0)
        interpolation.text = parts.map(\.text).joined(separator: separator.text)
        return JevCodeText(stringInterpolation: interpolation)
    }
}
