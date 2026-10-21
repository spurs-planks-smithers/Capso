// App/Feedback/ForkBranding.swift
import Foundation

/// Fork: the product name. The bundle name comes from `PRODUCT_NAME`
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
}
