import AnnotationKit
import Foundation

/// A feedback capture starts with the counter tool, so the first click drops
/// red dot 1 and no key is needed first (Drew, 2026-10-24). The editors keep
/// their last tool in `annotationLastTool`, which upstream's own editors read
/// too. The tool in use before the capture comes back when its editor closes.
@MainActor
struct FeedbackDefaultTool {
    static let key = "annotationLastTool"

    private let defaults: UserDefaults
    private let previous: String?

    /// Sets the counter tool and remembers the tool it replaces. Call it
    /// before the editor is made: the editor reads the tool when it opens.
    static func begin(defaults: UserDefaults = .standard) -> FeedbackDefaultTool {
        let tool = FeedbackDefaultTool(defaults: defaults, previous: defaults.string(forKey: key))
        defaults.set(AnnotationTool.counter.rawValue, forKey: key)
        return tool
    }

    func restore() {
        if let previous {
            defaults.set(previous, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
