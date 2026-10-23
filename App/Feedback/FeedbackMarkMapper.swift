// App/Feedback/FeedbackMarkMapper.swift
import AnnotationKit
import CoreGraphics
import FeedbackKit

/// Maps annotation objects to feedback marks in pixels of the exported PNG.
///
/// Annotation objects use the capture's pixel space with a top-left origin
/// (see `AnnotationRenderer`), the same space `ImageSizing.scale` expects.
@MainActor
enum FeedbackMarkMapper {
    static func marks(from objects: [any AnnotationObject], source: PixelSize, target: PixelSize) -> [FeedbackMark] {
        func box(_ rect: CGRect) -> FeedbackBox { ImageSizing.scale(rect, from: source, to: target) }
        func point(_ point: CGPoint) -> FeedbackPoint { ImageSizing.scale(point, from: source, to: target) }
        func span(_ start: CGPoint, _ end: CGPoint) -> CGRect {
            CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        }

        return objects.compactMap { object -> FeedbackMark? in
            switch object {
            case let counter as CounterObject:
                let circle = CGRect(
                    x: counter.center.x - counter.radius,
                    y: counter.center.y - counter.radius,
                    width: counter.radius * 2,
                    height: counter.radius * 2
                )
                return FeedbackMark(kind: .counter, badge: counter.number, box: box(circle), point: counter.tip.map(point))
            case let arrow as ArrowObject:
                return FeedbackMark(kind: .arrow, box: box(span(arrow.start, arrow.end)), point: point(arrow.end))
            case let line as LineObject:
                return FeedbackMark(kind: .line, box: box(span(line.start, line.end)), point: point(line.end))
            case let text as TextObject:
                return FeedbackMark(kind: .text, box: box(text.bounds), textOnImage: text.text)
            case let rectangle as RectangleObject:
                return FeedbackMark(kind: .rectangle, box: box(rectangle.rect))
            case let ellipse as EllipseObject:
                return FeedbackMark(kind: .ellipse, box: box(ellipse.rect))
            case let freehand as FreehandObject:
                return FeedbackMark(kind: .freehand, box: box(freehand.bounds))
            case let pixelate as PixelateObject:
                return FeedbackMark(kind: .pixelate, box: box(pixelate.rect))
            case let spotlight as SpotlightObject:
                return FeedbackMark(kind: .spotlight, box: box(spotlight.rect))
            default:
                return nil
            }
        }
    }
}
