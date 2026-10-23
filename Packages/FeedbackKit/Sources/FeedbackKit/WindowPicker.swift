// Packages/FeedbackKit/Sources/FeedbackKit/WindowPicker.swift
import CoreGraphics
import Foundation

/// One on-screen window, in global coordinates with a top-left origin.
public struct ScreenWindow: Equatable, Sendable {
    public var pid: Int32
    public var layer: Int
    public var bounds: CGRect
    public var title: String?
    public var ownerName: String?

    public init(pid: Int32, layer: Int, bounds: CGRect, title: String?, ownerName: String?) {
        self.pid = pid
        self.layer = layer
        self.bounds = bounds
        self.title = title
        self.ownerName = ownerName
    }
}

/// Finds the window under a capture, so the capture can be named after it.
public enum WindowPicker {
    /// The frontmost normal window (layer 0) that contains `point`, skipping
    /// windows of `excludingPID` (Capso's own overlay and editor).
    /// `windows` must be in front-to-back order, as CGWindowList returns them.
    public static func window(at point: CGPoint, in windows: [ScreenWindow], excludingPID: Int32) -> ScreenWindow? {
        windows.first { $0.layer == 0 && $0.pid != excludingPID && $0.bounds.contains(point) }
    }
}
