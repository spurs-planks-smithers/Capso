// Packages/JevKit/Sources/JevKit/Client/JevEndpoint.swift
import Foundation

/// The one place Nextshot sends requests to, and the pinned model.
public enum JevEndpoint {
    /// The only host any Nextshot request may reach.
    public static let host = "api.typesafe.ai"
    /// `POST https://api.typesafe.ai/v1/systemone` (docs.typesafe.ai/api/system-one).
    public static let systemOneURL = URL(string: "https://\(host)/v1/systemone")!
    /// Pinned in code, never read from a flag or a setting. TypeSafe's Models
    /// page says to send the versioned ID when thresholds were tuned on one
    /// version. A new model is a code change with new thresholds.
    public static let model = "jev-1.14.0"
    /// Sent only with a request that holds an image or a Box question.
    public static let imagesHeader = "TypeSafe-Danger-Zone-Images"
    /// TypeSafe's request id, kept for a support question.
    public static let requestIDHeader = "x-typesafe-request-id"
}
