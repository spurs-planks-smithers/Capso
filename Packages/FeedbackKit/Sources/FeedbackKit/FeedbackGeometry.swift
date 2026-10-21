// Packages/FeedbackKit/Sources/FeedbackKit/FeedbackGeometry.swift
import Foundation

/// A size in whole pixels.
public struct PixelSize: Codable, Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// A point in pixels of an exported PNG. The origin is the top-left corner.
public struct FeedbackPoint: Codable, Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// A box in pixels of an exported PNG. (x1, y1) is the top-left corner and
/// (x2, y2) the bottom-right corner, with the origin at the image's top-left.
public struct FeedbackBox: Codable, Equatable, Hashable, Sendable {
    public var x1: Int
    public var y1: Int
    public var x2: Int
    public var y2: Int

    public init(x1: Int, y1: Int, x2: Int, y2: Int) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }
}

extension FeedbackBox {
    var center: FeedbackPoint {
        FeedbackPoint(x: (x1 + x2) / 2, y: (y1 + y2) / 2)
    }

    func contains(_ point: FeedbackPoint) -> Bool {
        (x1...x2).contains(point.x) && (y1...y2).contains(point.y)
    }

    func intersects(_ other: FeedbackBox) -> Bool {
        x1 <= other.x2 && other.x1 <= x2 && y1 <= other.y2 && other.y1 <= y2
    }

    /// Distance from `point` to the nearest edge, or 0 when the point is inside.
    func distance(to point: FeedbackPoint) -> Double {
        let dx = max(x1 - point.x, 0, point.x - x2)
        let dy = max(y1 - point.y, 0, point.y - y2)
        return (Double(dx * dx + dy * dy)).squareRoot()
    }
}
