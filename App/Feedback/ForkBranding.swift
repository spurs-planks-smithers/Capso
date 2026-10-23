// App/Feedback/ForkBranding.swift
import AppKit

/// Fork: the product name and mark. The bundle name comes from `PRODUCT_NAME`
/// (`scripts/local-project.yml` sets "Nextshot"). Upstream menu text that
/// names "Capso" passes through `renamed(_:)`, so every locale keeps its
/// translation.
enum ForkBranding {
    static let name = "Nextshot"
    /// The menu bar title, for example "Nshot (2)".
    static let shortName = "Nshot"

    static func renamed(_ upstreamText: String) -> String {
        upstreamText.replacingOccurrences(of: "Capso", with: name)
    }

    /// The running build, for example "Nextshot 2026.10.22 (497)". The build
    /// scripts set both numbers from git (`scripts/nextshot-version.sh`).
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "n/a"
        let build = info?["CFBundleVersion"] as? String ?? "n/a"
        return "\(name) \(version) (\(build))"
    }

    /// The Nextshot mark (square and chevron) as a template image, 14 points
    /// tall like other menu bar icons. Both menu bar items use it, so no
    /// Capso logo shows. scripts/brand/make_nextshot_icon.py draws it. Falls
    /// back to a system symbol if the asset is missing.
    @MainActor
    static func menuBarMark(description: String, fallbackSymbol: String) -> NSImage? {
        guard let mark = NSImage(named: "NextshotMark")?.copy() as? NSImage else {
            return NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: description)
        }
        let height: CGFloat = 14
        mark.size = NSSize(width: (mark.size.width / mark.size.height * height).rounded(), height: height)
        mark.isTemplate = true
        mark.accessibilityDescription = description
        return mark
    }
}
