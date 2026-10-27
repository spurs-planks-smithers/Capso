import Foundation
import FeedbackKit

public enum SupportError: Error, Equatable, LocalizedError {
    case noCaptures, captureOpen, tooLarge, invalidInput, sensitiveContent, unreadableImage, incompleteOCR, invalidResponse, serviceUnavailable, requestFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .noCaptures: "This round has no saved captures."
        case .captureOpen: "Finish the open capture before submitting feedback."
        case .tooLarge: "This round exceeds the support upload limits. Submit a smaller round."
        case .invalidInput: "The note, email, or round data is not valid."
        case .sensitiveContent: "Possible sensitive information found. Create a capture without private information before submitting."
        case .unreadableImage: "A capture cannot be read. Nothing was uploaded."
        case .incompleteOCR: "The local privacy check could not finish. Nothing was uploaded."
        case .invalidResponse: "The feedback service returned an invalid response."
        case .serviceUnavailable: "Feedback submission is not available yet. Please try again later."
        case .requestFailed(let code): code == 429 ? "The feedback limit was reached. Please try again later." : "The feedback service could not complete this request."
        }
    }
}

public struct SupportApp: Codable, Sendable, Equatable {
    public let version: String
    public let build: String
    public let channel: String
    public let osVersion: String
    public init(version: String, build: String, channel: String, osVersion: String) {
        self.version = version; self.build = build; self.channel = channel; self.osVersion = osVersion
    }
}

public struct SupportItem: Codable, Sendable, Equatable {
    public let id: String
    public let instruction: String
}

public struct SupportCapture: Codable, Sendable, Equatable {
    public let index: Int
    public let imageFile: String
    public let width: Int
    public let height: Int
    public let note: String
    public let items: [SupportItem]

    public init(capture: FeedbackCapture, imageFile: String, size: PixelSize) {
        index = capture.index
        self.imageFile = imageFile
        width = size.width; height = size.height
        note = capture.note ?? ""
        items = FeedbackItems.split(capture).items.map { SupportItem(id: $0.id, instruction: $0.badge.instruction ?? "") }
    }
}

public struct SupportManifest: Encodable, Sendable, Equatable {
    public let schemaVersion = 1
    public let app: SupportApp
    public let note: String
    public let contactEmail: String?
    public let captures: [SupportCapture]
}

public struct SupportPackage: Sendable {
    public let url: URL
    public let bytes: Int
    public let sha256: String
    public let idempotencyKey: String
    public let note: String
    public let contactEmail: String?
    public let captureCount: Int
    public func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

public enum SupportInput {
    public static func validate(note: String, contactEmail: String?) throws {
        guard note.count <= SupportLimits.noteCharacters,
              !note.contains(where: { $0.isNewline || $0.unicodeScalars.contains(where: { $0.value < 32 }) }) else { throw SupportError.invalidInput }
        if let contactEmail, !contactEmail.isEmpty {
            guard contactEmail.utf8.count <= 254,
                  contactEmail.range(of: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil else { throw SupportError.invalidInput }
        }
    }
}
