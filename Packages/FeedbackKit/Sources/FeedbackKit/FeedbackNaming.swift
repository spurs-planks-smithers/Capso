// Packages/FeedbackKit/Sources/FeedbackKit/FeedbackNaming.swift
import Foundation

/// File and folder names inside `~/Feedback`.
public enum FeedbackNaming {
    public static let defaultSlug = "feedback"
    public static let maxSlugLength = 40

    /// Lowercase ASCII letters and digits joined by single hyphens.
    /// Accents are folded ("Café" becomes "cafe"). Other characters split words.
    public static func slug(from name: String) -> String {
        let folded = name.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()

        var slug = ""
        var needsHyphen = false
        for scalar in folded.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if needsHyphen, !slug.isEmpty {
                    slug.append("-")
                }
                needsHyphen = false
                slug.unicodeScalars.append(scalar)
            } else {
                needsHyphen = true
            }
        }

        if slug.count > maxSlugLength {
            slug = String(slug.prefix(maxSlugLength))
            while slug.hasSuffix("-") {
                slug.removeLast()
            }
        }
        return slug.isEmpty ? defaultSlug : slug
    }

    /// `yyyy-MM-dd-HHmm-<slug>` in the given time zone.
    public static func folderName(startedAt: Date, slug: String, timeZone: TimeZone) -> String {
        "\(format(startedAt, "yyyy-MM-dd-HHmm", timeZone: timeZone))-\(slug)"
    }

    /// `base`, or `base-2`, `base-3`, and so on when a name is taken.
    public static func uniqueName(_ base: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(base) else { return base }
        var suffix = 2
        while isTaken("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }

    /// The name a person sees: "Capture: <window title>, 2026-10-20 22:24 PDT".
    /// The app name stands in for a missing window title. With `quoted`, the
    /// title sits in double quotes (its own quotes become single quotes), so
    /// a page title cannot pass for bundle structure in `manifest.md`.
    public static func captureName(
        windowTitle: String?,
        sourceApp: String?,
        capturedAt: Date,
        timeZone: TimeZone,
        quoted: Bool = false
    ) -> String {
        let time = format(capturedAt, "yyyy-MM-dd HH:mm zzz", timeZone: timeZone)
        guard let label = label(windowTitle: windowTitle, sourceApp: sourceApp) else {
            return "Capture: \(time)"
        }
        let shown = quoted ? "\"\(label.replacingOccurrences(of: "\"", with: "'"))\"" : label
        return "Capture: \(shown), \(time)"
    }

    /// The file name without extension: "2224-pricing-acme". The session
    /// folder already holds the date.
    public static func captureFileStem(windowTitle: String?, sourceApp: String?, capturedAt: Date, timeZone: TimeZone) -> String {
        let time = format(capturedAt, "HHmm", timeZone: timeZone)
        let name = label(windowTitle: windowTitle, sourceApp: sourceApp).map(slug(from:)) ?? "capture"
        return "\(time)-\(name)"
    }

    private static func label(windowTitle: String?, sourceApp: String?) -> String? {
        ScreenText.field(windowTitle, maxScalars: maxLabelLength)
            ?? ScreenText.field(sourceApp, maxScalars: maxLabelLength)
    }

    private static let maxLabelLength = 80

    private static func format(_ date: Date, _ pattern: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
