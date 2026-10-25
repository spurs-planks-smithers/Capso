// Packages/FeedbackKit/Sources/FeedbackKit/FeedbackItems.swift
import Foundation

/// A numbered badge, plus the box or ellipse it sits on, if any.
/// Item `2.3` is badge 3 in capture 2.
public struct FeedbackItem: Equatable, Sendable {
    public var captureIndex: Int
    public var badge: FeedbackMark
    public var shape: FeedbackMark?

    public var id: String { "\(captureIndex).\(badge.badge ?? 0)" }

    /// The shape's OCR text names the marked region best, so it wins.
    public var ocrText: String? { shape?.ocrText ?? badge.ocrText }

    /// The box that holds the badge, the shape it sits on, and the point its
    /// arrow aims at. The preview crop and the item crop both start from it.
    public var focus: FeedbackBox {
        var focus = badge.box
        if let shape {
            focus = focus.union(shape.box)
        }
        if let tip = badge.point {
            focus = focus.union(FeedbackBox(x1: tip.x, y1: tip.y, x2: tip.x, y2: tip.y))
        }
        return focus
    }
}

public enum FeedbackItems {
    /// Shapes a badge can label. Other marks are listed on their own.
    static let shapeKinds: Set<FeedbackMark.Kind> = [.rectangle, .ellipse]

    /// Splits a capture's marks into items and the marks left over.
    ///
    /// A shape goes to the touching badge whose center is nearest to it
    /// (lower badge number on a tie). Each badge takes at most one shape.
    public static func split(_ capture: FeedbackCapture) -> (items: [FeedbackItem], otherMarks: [FeedbackMark]) {
        let badges = capture.marks.indices.filter {
            capture.marks[$0].kind == .counter && capture.marks[$0].badge != nil
        }

        var shapeForBadge: [Int: Int] = [:]
        for shapeIndex in capture.marks.indices where shapeKinds.contains(capture.marks[shapeIndex].kind) {
            let shapeBox = capture.marks[shapeIndex].box
            let best = badges
                .filter { shapeForBadge[$0] == nil && capture.marks[$0].box.intersects(shapeBox) }
                .min { lhs, rhs in
                    let left = shapeBox.distance(to: capture.marks[lhs].box.center)
                    let right = shapeBox.distance(to: capture.marks[rhs].box.center)
                    if left != right { return left < right }
                    return (capture.marks[lhs].badge ?? 0) < (capture.marks[rhs].badge ?? 0)
                }
            if let best {
                shapeForBadge[best] = shapeIndex
            }
        }

        let items = badges
            .sorted { (capture.marks[$0].badge ?? 0, $0) < (capture.marks[$1].badge ?? 0, $1) }
            .map { badgeIndex in
                FeedbackItem(
                    captureIndex: capture.index,
                    badge: capture.marks[badgeIndex],
                    shape: shapeForBadge[badgeIndex].map { capture.marks[$0] }
                )
            }

        let used = Set(badges).union(shapeForBadge.values)
        let otherMarks = capture.marks.indices.filter { !used.contains($0) }.map { capture.marks[$0] }
        return (items, otherMarks)
    }
}
