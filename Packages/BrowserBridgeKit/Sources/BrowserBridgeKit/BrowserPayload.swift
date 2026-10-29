import CryptoKit
import FeedbackKit
import Foundation
import ImageIO

public enum BrowserBridgeError: Error { case invalid, unavailable, identity, oversized }

public struct BrowserAsset: Codable, Sendable {
    public let name: String
    public let mime: String
    public let bytes: Data
}

public struct BrowserMark: Codable, Sendable {
    public let id: Int
    public let kind: String
    public let x: Double
    public let y: Double
    public let endX: Double?
    public let endY: Double?
    public let note: String
    public let elementId: String?
}

public struct BrowserKeyFrame: Codable, Sendable {
    public let at: Double
    public let file: String
    public let width: Int
    public let height: Int
}

public struct BrowserCapture: Codable, Sendable {
    public let id: String
    public let kind: String
    public let createdAt: String
    public let title: String
    public let width: Int
    public let height: Int
    public let imageFile: String
    public let cleanImageFile: String
    public let keyFrames: [BrowserKeyFrame]?
    public let marks: [BrowserMark]
    public let note: String
}

/// The browser sends one selected capture. Raw page evidence stays in a sidecar.
public struct BrowserPayload: Decodable, Sendable {
    public let schema: String
    public let schemaVersion: Int
    public let capture: BrowserCapture
    public let assets: [BrowserAsset]

    public static let maximumBytes = 16 * 1024 * 1024
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    public static func decode(_ data: Data, id: String, digest: String) throws -> BrowserPayload {
        guard data.count <= maximumBytes, digest == Self.digest(data), UUID(uuidString: id) != nil else { throw BrowserBridgeError.invalid }
        let value = try JSONDecoder().decode(Self.self, from: data)
        let c = value.capture
        guard value.schema == "nextshot.browser", value.schemaVersion == 1, c.id == id,
              ["capture", "rolling"].contains(c.kind), (1...16000).contains(c.width), (1...16000).contains(c.height),
              c.width * c.height <= 40_000_000, c.title.count <= 200, c.note.count <= 20000, c.marks.count <= 100,
              Self.date(c.createdAt) != nil else { throw BrowserBridgeError.invalid }
        guard !value.assets.isEmpty, value.assets.count <= 100 else { throw BrowserBridgeError.invalid }
        var names = Set<String>()
        for asset in value.assets {
            guard safeName(asset.name), asset.name.hasPrefix(id), names.insert(asset.name).inserted,
                  ["image/jpeg", "image/png", "image/webp", "image/gif", "video/webm", "video/mp4"].contains(asset.mime),
                  !asset.bytes.isEmpty, asset.bytes.count <= maximumBytes else { throw BrowserBridgeError.invalid }
        }
        for name in [c.imageFile, c.cleanImageFile] {
            guard let asset = value.assets.first(where: { $0.name == name }), asset.mime.hasPrefix("image/"),
                  let image = CGImageSourceCreateWithData(asset.bytes as CFData, nil), CGImageSourceGetCount(image) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                  properties[kCGImagePropertyPixelWidth] as? Int == c.width,
                  properties[kCGImagePropertyPixelHeight] as? Int == c.height else { throw BrowserBridgeError.invalid }
        }
        guard (c.keyFrames?.count ?? 0) <= 12 else { throw BrowserBridgeError.invalid }
        for frame in c.keyFrames ?? [] {
            guard frame.at.isFinite, frame.at >= 0, (1...16000).contains(frame.width), (1...16000).contains(frame.height),
                  frame.width * frame.height <= 40_000_000,
                  let asset = value.assets.first(where: { $0.name == frame.file }),
                  ["image/jpeg", "image/png", "image/webp"].contains(asset.mime),
                  let image = CGImageSourceCreateWithData(asset.bytes as CFData, nil), CGImageSourceGetCount(image) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                  properties[kCGImagePropertyPixelWidth] as? Int == frame.width,
                  properties[kCGImagePropertyPixelHeight] as? Int == frame.height else { throw BrowserBridgeError.invalid }
        }
        for (offset, mark) in c.marks.enumerated() {
            guard mark.id == offset + 1, ["dot", "arrow", "box"].contains(mark.kind), mark.note.count <= 10000,
                  mark.x.isFinite, mark.y.isFinite, (0...Double(c.width)).contains(mark.x), (0...Double(c.height)).contains(mark.y),
                  mark.endX.map({ $0.isFinite && (0...Double(c.width)).contains($0) }) ?? true,
                  mark.endY.map({ $0.isFinite && (0...Double(c.height)).contains($0) }) ?? true else { throw BrowserBridgeError.invalid }
            guard mark.kind == "dot" || (mark.endX != nil && mark.endY != nil) else { throw BrowserBridgeError.invalid }
        }
        // Bound all nested evidence before it becomes a native attachment.
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let capture = object["capture"] as? [String: Any],
              let elements = capture["elements"] as? [[String: Any]], elements.count <= 2000,
              let actions = capture["actions"] as? [[String: Any]], actions.count <= 2000,
              let diagnostics = capture["diagnostics"] as? [[String: Any]], diagnostics.count <= 2000 else { throw BrowserBridgeError.invalid }
        let clip = capture["clip"] as? [String: Any]
        let media = clip?["mediaFile"] as? String
        let referenced = Set([c.imageFile, c.cleanImageFile] + (c.keyFrames ?? []).map(\.file) + [media].compactMap { $0 })
        guard Set((c.keyFrames ?? []).map(\.file)).count == (c.keyFrames?.count ?? 0) else { throw BrowserBridgeError.invalid }
        guard names == referenced else { throw BrowserBridgeError.invalid }
        _ = try BrowserEvidence.capture(capture)
        return value
    }

    public static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    public static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 180 && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    public func nativeCapture(index: Int, digest: String, evidenceFile: String) -> FeedbackCapture {
        let c = capture
        let date = Self.date(c.createdAt) ?? Date()
        var marks: [FeedbackMark] = []
        for m in c.marks {
            let x = Int(m.x.rounded()), y = Int(m.y.rounded()), ex = Int((m.endX ?? m.x).rounded()), ey = Int((m.endY ?? m.y).rounded())
            if m.kind != "dot" {
                marks.append(FeedbackMark(kind: m.kind == "box" ? .rectangle : .arrow,
                    box: FeedbackBox(x1: min(x, ex), y1: min(y, ey), x2: max(x, ex), y2: max(y, ey)),
                    point: m.kind == "arrow" ? FeedbackPoint(x: ex, y: ey) : nil))
            }
            marks.append(FeedbackMark(kind: .counter, badge: m.id,
                box: FeedbackBox(x1: max(0, x - 12), y1: max(0, y - 12), x2: min(c.width, x + 12), y2: min(c.height, y + 12)), instruction: m.note))
        }
        var result = FeedbackCapture(index: index, imageFile: c.imageFile, cleanImageFile: c.cleanImageFile,
            size: PixelSize(width: c.width, height: c.height), capturedAt: date, sourceApp: "Browser", windowTitle: BrowserEvidence.text(c.title, limit: 200),
            note: c.note, marks: marks)
        result.browserImportID = c.id
        result.browserDigest = digest
        result.browserEvidenceFile = evidenceFile
        result.browserAssetFiles = assets.map(\.name).filter { $0 != c.imageFile && $0 != c.cleanImageFile }
        return result
    }

    public static func evidence(from data: Data) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let capture = object["capture"] as? [String: Any] else { throw BrowserBridgeError.invalid }
        return try JSONSerialization.data(withJSONObject: ["schema": "nextshot.browser", "schemaVersion": 1, "capture": BrowserEvidence.capture(capture)], options: [.prettyPrinted, .sortedKeys])
    }
}
