// Packages/FeedbackKit/Sources/FeedbackKit/OCRMatcher.swift
import Foundation

/// Finds the OCR text under each mark. The agent searches the repository for
/// this text to locate the item in code.
///
/// - Region marks (box, ellipse, freehand, pixelate, spotlight): the lines whose
///   center lies inside the mark, in reading order.
/// - Arrows, lines, and badges with a tip: the line at the head or tip, else
///   the nearest line within `maxDistance` pixels.
/// - Badges with no tip: the lines that touch the badge, else the nearest line
///   within `maxDistance` pixels of its center.
/// - Text marks: none. Their own text is `textOnImage`.
public enum OCRMatcher {
    public static let defaultMaxDistance = 60

    public static func assignText(
        to marks: [FeedbackMark],
        lines: [FeedbackTextLine],
        maxDistance: Int = defaultMaxDistance
    ) -> [FeedbackMark] {
        marks.map { mark in
            var mark = mark
            mark.ocrText = text(for: mark, lines: lines, maxDistance: Double(maxDistance))
            return mark
        }
    }

    /// Drops every OCR line that a Redact (`.pixelate`) mark touches, so
    /// redacted text never reaches the bundle files.
    public static func removingRedacted(_ lines: [FeedbackTextLine], marks: [FeedbackMark]) -> [FeedbackTextLine] {
        let redactions = marks.filter { $0.kind == .pixelate }.map(\.box)
        guard !redactions.isEmpty else { return lines }
        return lines.filter { line in !redactions.contains { $0.intersects(line.box) } }
    }

    private static func text(for mark: FeedbackMark, lines: [FeedbackTextLine], maxDistance: Double) -> String? {
        switch mark.kind {
        case .text:
            return nil
        case .rectangle, .ellipse, .freehand, .pixelate, .spotlight:
            return joined(lines.filter { mark.box.contains($0.box.center) })
        case .arrow, .line:
            guard let head = mark.point else { return nil }
            return text(at: head, lines: lines, maxDistance: maxDistance)
        case .counter:
            if let tip = mark.point {
                return text(at: tip, lines: lines, maxDistance: maxDistance)
            }
            let touching = lines.filter { $0.box.intersects(mark.box) }
            if !touching.isEmpty {
                return joined(touching)
            }
            return nearest(to: mark.box.center, lines: lines, maxDistance: maxDistance)?.text
        }
    }

    private static func text(at point: FeedbackPoint, lines: [FeedbackTextLine], maxDistance: Double) -> String? {
        if let hit = lines.first(where: { $0.box.contains(point) }) {
            return hit.text
        }
        return nearest(to: point, lines: lines, maxDistance: maxDistance)?.text
    }

    private static func nearest(to point: FeedbackPoint, lines: [FeedbackTextLine], maxDistance: Double) -> FeedbackTextLine? {
        lines
            .map { (line: $0, distance: $0.box.distance(to: point)) }
            .filter { $0.distance <= maxDistance }
            .min { $0.distance < $1.distance }?
            .line
    }

    private static func joined(_ lines: [FeedbackTextLine]) -> String? {
        guard !lines.isEmpty else { return nil }
        return lines
            .sorted { ($0.box.y1, $0.box.x1) < ($1.box.y1, $1.box.x1) }
            .map(\.text)
            .joined(separator: " ")
    }
}
