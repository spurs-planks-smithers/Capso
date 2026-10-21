// Packages/FeedbackKit/Sources/FeedbackKit/FeedbackModel.swift
import Foundation

/// A feedback session: one folder under the store's root with numbered captures.
/// `feedback.json` stores this value and is the bundle's source of truth.
public struct FeedbackSession: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var name: String
    public var slug: String
    public var folderName: String
    public var startedAt: Date
    public var endedAt: Date?
    public var captures: [FeedbackCapture]

    public init(
        name: String,
        slug: String,
        folderName: String,
        startedAt: Date,
        endedAt: Date? = nil,
        captures: [FeedbackCapture] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.name = name
        self.slug = slug
        self.folderName = folderName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.captures = captures
    }

    /// Items are the numbered badges across all captures.
    public var itemCount: Int {
        captures.reduce(0) { $0 + $1.badgeNumbers.count }
    }
}

/// One saved capture. All coordinates are pixels of `imageFile`.
public struct FeedbackCapture: Codable, Equatable, Sendable {
    /// 1-based position in the session. It is the item prefix K in the
    /// manifest; file names use the capture time and window title instead.
    public var index: Int
    public var imageFile: String
    public var cleanImageFile: String
    public var size: PixelSize
    public var capturedAt: Date
    public var sourceApp: String?
    public var windowTitle: String?
    /// The capture note after badge instructions are taken out of it.
    public var note: String?
    /// All on-device OCR text of the clean image.
    public var ocrText: String?
    public var marks: [FeedbackMark]

    public init(
        index: Int,
        imageFile: String,
        cleanImageFile: String,
        size: PixelSize,
        capturedAt: Date,
        sourceApp: String? = nil,
        windowTitle: String? = nil,
        note: String? = nil,
        ocrText: String? = nil,
        marks: [FeedbackMark] = []
    ) {
        self.index = index
        self.imageFile = imageFile
        self.cleanImageFile = cleanImageFile
        self.size = size
        self.capturedAt = capturedAt
        self.sourceApp = sourceApp
        self.windowTitle = windowTitle
        self.note = note
        self.ocrText = ocrText
        self.marks = marks
    }

    public var badgeNumbers: Set<Int> {
        Set(marks.compactMap(\.badge))
    }
}

/// One annotation on a capture.
///
/// - `box` is the mark's bounds. For `.arrow` and `.line`, `box` spans the two
///   end points and `point` is the head.
/// - For `.counter`, `box` is the badge circle and `point` is the arrow tip,
///   if the badge has one.
public struct FeedbackMark: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case counter
        case rectangle
        case ellipse
        case arrow
        case line
        case freehand
        case text
        case pixelate
        case spotlight
    }

    public var kind: Kind
    public var badge: Int?
    public var box: FeedbackBox
    public var point: FeedbackPoint?
    /// Text typed on the image with the Text tool.
    public var textOnImage: String?
    /// On-device OCR text under or next to the mark.
    public var ocrText: String?
    /// The written instruction for a badge, from the capture note.
    public var instruction: String?

    public init(
        kind: Kind,
        badge: Int? = nil,
        box: FeedbackBox,
        point: FeedbackPoint? = nil,
        textOnImage: String? = nil,
        ocrText: String? = nil,
        instruction: String? = nil
    ) {
        self.kind = kind
        self.badge = badge
        self.box = box
        self.point = point
        self.textOnImage = textOnImage
        self.ocrText = ocrText
        self.instruction = instruction
    }
}

/// One line of on-device OCR text, in pixels of the exported PNG.
public struct FeedbackTextLine: Equatable, Sendable {
    public var text: String
    public var box: FeedbackBox

    public init(text: String, box: FeedbackBox) {
        self.text = text
        self.box = box
    }
}
