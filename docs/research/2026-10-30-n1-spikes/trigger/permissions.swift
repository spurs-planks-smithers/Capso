// N1 spike 1: which macOS permissions does each way of learning about Chrome need?
// Build: swiftc -O permissions.swift -o permissions
// It reads state only and never prompts. The answers describe the process that runs it
// (here a terminal child of the Claude desktop app), not Nextshot Dev.
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

var report: [String: Any] = [:]
// No permission: the frontmost app and its bundle ID (what CaptureCoordinator already records).
let front = NSWorkspace.shared.frontmostApplication
report["frontmostApp"] = front?.bundleIdentifier ?? "none"
// Accessibility trust gates the AX tree of Chrome's page (element roles, names and frames).
report["accessibilityTrusted"] = AXIsProcessTrusted()
// Screen Recording gates window titles of other apps and pixel capture.
report["screenRecordingGranted"] = CGPreflightScreenCaptureAccess()
// Input Monitoring gates a passive key listener that would let Chrome see the same key press.
report["inputMonitoringGranted"] = CGPreflightListenEventAccess()
// Chrome running state, without any permission.
report["chromeRunning"] = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty
// Window list owner names are readable without Screen Recording; titles are not.
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let chromeWindows = windows.filter { ($0[kCGWindowOwnerName as String] as? String) == "Google Chrome" }
report["chromeOnScreenWindows"] = chromeWindows.count
report["chromeWindowTitlesVisible"] = chromeWindows.contains { !(($0[kCGWindowName as String] as? String) ?? "").isEmpty }
print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
