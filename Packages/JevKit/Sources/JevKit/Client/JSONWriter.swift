// Packages/JevKit/Sources/JevKit/Client/JSONWriter.swift
import Foundation

/// Writes request JSON by hand, so object keys keep their order and the body
/// is the same on every run. TypeSafe accepts UTF-8 JSON without a byte order
/// mark, and finite numbers only (docs.typesafe.ai/api/errors).
struct JSONWriter {
    private(set) var text = ""
    /// The asset reference for each image id. An image is written as its
    /// reference string, and TypeSafe puts the image in its place.
    let references: [UUID: String]

    init(references: [UUID: String] = [:]) {
        self.references = references
    }

    mutating func write(_ value: JevValue) throws {
        switch value {
        case .reviewer(let string), .screen(let string):
            writeString(string)
        case .code(let code):
            writeString(code.text)
        case .number(let number):
            try writeNumber(number)
        case .bool(let bool):
            text += bool ? "true" : "false"
        case .image(let image):
            guard let reference = references[image.id] else { throw JevError(.badRequest) }
            writeString(reference)
        case .object(let fields):
            try writeObject(fields.map { field in (field.0.text, { (writer: inout JSONWriter) in try writer.write(field.1) }) })
        case .array(let items):
            text += "["
            for (offset, item) in items.enumerated() {
                if offset > 0 { text += "," }
                try write(item)
            }
            text += "]"
        }
    }

    /// An object whose values are written by closures, in order.
    mutating func writeObject(_ fields: [(String, (inout JSONWriter) throws -> Void)]) throws {
        text += "{"
        for (offset, field) in fields.enumerated() {
            if offset > 0 { text += "," }
            writeString(field.0)
            text += ":"
            try field.1(&self)
        }
        text += "}"
    }

    mutating func writeString(_ string: String) {
        text += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case "\u{08}": text += "\\b"
            case "\u{0C}": text += "\\f"
            default:
                if scalar.value < 0x20 || scalar.value == 0x2028 || scalar.value == 0x2029 {
                    text += String(format: "\\u%04x", scalar.value)
                } else {
                    text.unicodeScalars.append(scalar)
                }
            }
        }
        text += "\""
    }

    mutating func writeNumber(_ number: Double) throws {
        guard number.isFinite else { throw JevError(.badRequest) }
        if number == number.rounded(), abs(number) < 1e15 {
            text += String(Int64(number))
        } else {
            text += "\(number)"
        }
    }
}
