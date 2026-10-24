// Packages/JevKit/Sources/JevKit/Client/JevRequestEncoder.swift
import Foundation

/// Turns a `JevRequest` into an HTTP body, after the checks that catch a
/// code bug before anything is sent.
enum JevRequestEncoder {
    static let maxImages = 8
    static let maxBodyBytes = 32 << 20

    struct Encoded {
        var body: Data
        var contentType: String
        var needsImagesHeader: Bool
    }

    static func encode(_ request: JevRequest, model: String = JevEndpoint.model) throws -> Encoded {
        try check(request)

        let images = request.images
        var references: [UUID: String] = [:]
        var partNames: [UUID: String] = [:]
        for (offset, image) in images.enumerated() {
            references[image.id] = "nshot-img-\(image.id.uuidString.lowercased())"
            partNames[image.id] = "image-\(offset + 1)"
        }

        var writer = JSONWriter(references: references)
        var fields: [(String, (inout JSONWriter) throws -> Void)] = [
            ("model", { $0.writeString(model) }),
            ("state", { try $0.write(request.state) }),
            ("questions", { writer in
                try writer.writeObject(request.questions.map { entry in
                    (entry.id, { try writeQuestion(entry.question, into: &$0) })
                })
            }),
        ]
        if !images.isEmpty {
            fields.append(("assets", { writer in
                try writer.writeObject(images.map { image in
                    let reference = references[image.id] ?? ""
                    let part = partNames[image.id] ?? ""
                    return (reference, { try $0.write(.fields(["type": "image", "part": .code(part)])) })
                })
            }))
        }
        try writer.writeObject(fields)
        let json = Data(writer.text.utf8)

        let encoded: Encoded
        if images.isEmpty {
            encoded = Encoded(body: json, contentType: "application/json", needsImagesHeader: request.needsImagesHeader)
        } else {
            var parts = [MultipartBody.Part(name: "request", contentType: "application/json", fileName: nil, data: json)]
            for image in images {
                let part = partNames[image.id] ?? ""
                parts.append(MultipartBody.Part(name: part, contentType: "image/png", fileName: "\(part).png", data: image.png))
            }
            let body = MultipartBody(parts: parts)
            encoded = Encoded(body: body.data, contentType: body.contentType, needsImagesHeader: true)
        }
        guard encoded.body.count <= maxBodyBytes else { throw JevError(.badRequest) }
        return encoded
    }

    /// The checks before send. A failure is a bug in the job's code.
    static func check(_ request: JevRequest) throws {
        guard !request.questions.isEmpty else { throw JevError(.badRequest) }
        var ids = Set<String>()
        for entry in request.questions {
            guard isValidID(entry.id), ids.insert(entry.id).inserted else { throw JevError(.badRequest) }
            switch entry.question.kind {
            case .choice(let options):
                guard (1...255).contains(options.count),
                      Set(options.map(\.name)).count == options.count,
                      options.allSatisfy({ !$0.name.isEmpty })
                else { throw JevError(.badRequest) }
            case .score(let levels):
                guard (1...10).contains(levels.count) else { throw JevError(.badRequest) }
            case .box:
                guard !request.images.isEmpty else { throw JevError(.badRequest) }
            case .noul:
                break
            }
        }
        guard request.images.count <= maxImages else { throw JevError(.badRequest) }
        for image in request.images {
            guard (JevImage.minSide...JevImage.maxSide).contains(image.size.width),
                  (JevImage.minSide...JevImage.maxSide).contains(image.size.height),
                  !image.png.isEmpty
            else { throw JevError(.badRequest) }
        }
    }

    static func isValidID(_ id: String) -> Bool {
        (1...64).contains(id.count) && id.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII || "_.-".unicodeScalars.contains(scalar)
        }
    }

    private static func writeQuestion(_ question: JevQuestion, into writer: inout JSONWriter) throws {
        switch question.kind {
        case .noul(let yes, let no):
            var fields: [(String, (inout JSONWriter) throws -> Void)] = [
                ("type", { $0.writeString("noul") }),
                ("instructions", { try $0.write(question.instructions) }),
            ]
            if yes != nil || no != nil {
                var criteria: [(String, JevValue)] = []
                if let yes { criteria.append(("true", yes)) }
                if let no { criteria.append(("false", no)) }
                fields.append(("criteria", { try $0.write(.object(criteria)) }))
            }
            try writer.writeObject(fields)
        case .choice(let options):
            try writer.writeObject([
                ("type", { $0.writeString("choice") }),
                ("instructions", { try $0.write(question.instructions) }),
                ("criteria", { try $0.write(.object(options.map { ($0.name, $0.description) })) }),
            ])
        case .score(let levels):
            try writer.writeObject([
                ("type", { $0.writeString("score") }),
                ("instructions", { try $0.write(question.instructions) }),
                ("criteria", { try $0.write(.array(levels)) }),
            ])
        case .box:
            try writer.writeObject([
                ("type", { $0.writeString("box") }),
                ("instructions", { try $0.write(question.instructions) }),
            ])
        }
    }
}
