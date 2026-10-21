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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(formatter.string(from: startedAt))-\(slug)"
    }

    /// `base`, or `base-2`, `base-3`, and so on when a name is taken.
    public static func uniqueFolderName(_ base: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(base) else { return base }
        var suffix = 2
        while isTaken("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }

    public static func imageFileName(index: Int) -> String {
        "\(paddedIndex(index)).png"
    }

    public static func cleanImageFileName(index: Int) -> String {
        "\(paddedIndex(index))-clean.png"
    }

    static func paddedIndex(_ index: Int) -> String {
        String(format: "%03d", index)
    }
}
