// App/Feedback/FeedbackWindowTitle.swift
import AppKit
import CaptureKit
import FeedbackKit

/// Fork: finds the window under a capture, so the capture can be named after
/// it ("Capture: Pricing | Acme, ..."). Reads the on-screen window list
/// locally. Window titles need the Screen Recording grant, which Capso has.
enum FeedbackWindowTitle {
    static func window(for result: CaptureResult) -> ScreenWindow? {
        // captureRect is in display points with a top-left origin. The window
        // list uses global points with a top-left origin.
        let display = CGDisplayBounds(result.displayID)
        let center = CGPoint(x: display.minX + result.captureRect.midX, y: display.minY + result.captureRect.midY)

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let windows = list.compactMap { entry -> ScreenWindow? in
            guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let boundsInfo = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo) else { return nil }
            return ScreenWindow(
                pid: pid,
                layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                bounds: bounds,
                title: entry[kCGWindowName as String] as? String,
                ownerName: entry[kCGWindowOwnerName as String] as? String
            )
        }
        return WindowPicker.window(at: center, in: windows, excludingPID: ProcessInfo.processInfo.processIdentifier)
    }
}
