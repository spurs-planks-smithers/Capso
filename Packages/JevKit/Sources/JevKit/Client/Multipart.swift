// Packages/JevKit/Sources/JevKit/Client/Multipart.swift
import Foundation

/// A `multipart/form-data` body in TypeSafe's form (docs.typesafe.ai/images,
/// "Over HTTP"): the JSON request first, in a part named `request`, then one
/// part per image.
struct MultipartBody {
    struct Part {
        var name: String
        var contentType: String
        var fileName: String?
        var data: Data
    }

    let boundary: String
    private(set) var data = Data()

    /// Picks a boundary that appears in no part, then writes every part.
    init(parts: [Part]) {
        var boundary = "nextshot-\(UUID().uuidString)"
        while parts.contains(where: { $0.data.range(of: Data(boundary.utf8)) != nil }) {
            boundary = "nextshot-\(UUID().uuidString)"
        }
        self.boundary = boundary

        for part in parts {
            var header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(part.name)\""
            if let fileName = part.fileName {
                header += "; filename=\"\(fileName)\""
            }
            header += "\r\nContent-Type: \(part.contentType)\r\n\r\n"
            data.append(Data(header.utf8))
            data.append(part.data)
            data.append(Data("\r\n".utf8))
        }
        data.append(Data("--\(boundary)--\r\n".utf8))
    }

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }
}
