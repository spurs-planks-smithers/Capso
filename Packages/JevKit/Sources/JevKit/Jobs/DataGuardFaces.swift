// Packages/JevKit/Sources/JevKit/Jobs/DataGuardFaces.swift
import CoreGraphics
import FeedbackKit
import Foundation
import Vision

/// One face the finder found. `box` is in the image's pixels, origin top left.
public struct DataGuardFace: Equatable, Sendable {
    public var box: FeedbackBox
    public var confidence: Double

    public init(box: FeedbackBox, confidence: Double) {
        self.box = box
        self.confidence = confidence
    }
}

/// Finds faces in an image on the Mac. The job takes a finder as a parameter,
/// so tests use a stub: a face photo is private data, so no test holds one.
public struct DataGuardFaceFinder: Sendable {
    private let find: @Sendable (CGImage) throws -> [DataGuardFace]

    public init(_ find: @escaping @Sendable (CGImage) throws -> [DataGuardFace]) {
        self.find = find
    }

    public func faces(in image: CGImage) throws -> [DataGuardFace] {
        try find(image)
    }

    /// Apple Vision's face rectangle request. It runs on the Mac and sends
    /// nothing.
    public static let vision = DataGuardFaceFinder { image in
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let width = Double(image.width)
        let height = Double(image.height)
        return (request.results ?? []).map { face in
            // Vision gives fractions of the image, origin bottom left.
            let rect = face.boundingBox
            return DataGuardFace(
                box: FeedbackBox(
                    x1: Int((rect.minX * width).rounded(.down)),
                    y1: Int(((1 - rect.maxY) * height).rounded(.down)),
                    x2: Int((rect.maxX * width).rounded(.up)),
                    y2: Int(((1 - rect.minY) * height).rounded(.up))
                ),
                confidence: Double(face.confidence)
            )
        }
    }
}
