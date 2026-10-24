// Packages/JevKit/Sources/JevKit/Client/JevError.swift
import Foundation

/// Why a job did not run or did not finish. `jev.json` stores the raw value.
public enum JevFailureReason: String, Codable, Sendable, CaseIterable {
    /// The capture's time budget ended.
    case timeout
    /// No network, host not found, or a TLS failure.
    case offline
    /// HTTP 429 with no time left to retry.
    case rateLimited
    /// HTTP 529 with no time left to retry.
    case overloaded
    /// Another 5xx, or 408, with no time left to retry.
    case server
    /// HTTP 400, 413, 415, or 422, or a request that failed the checks before
    /// send. A code bug: never retried.
    case badRequest
    /// HTTP 401 or 403. Requests pause until the next app launch.
    case unauthorized
    /// The response failed a type or range check.
    case invalidResponse
    /// The response came from a model other than the pinned one.
    case modelMismatch
    /// No usable key in the Keychain.
    case noKey
    /// The job needs a data kind without consent, or a request held one.
    case consent
    /// Requests are paused after failures in a row, or after a 401.
    case paused
    /// The per-capture or per-day request cap is reached.
    case capReached
    /// The job threw an error of its own, or returned a bad file name.
    case jobError
}

/// The one error type the client and the runner throw. It holds a reason
/// and an HTTP status, never a body, a header, or the key, so it is safe
/// to log and to store.
public struct JevError: Error, Equatable, Sendable, CustomStringConvertible {
    public var reason: JevFailureReason
    public var status: Int?

    public init(_ reason: JevFailureReason, status: Int? = nil) {
        self.reason = reason
        self.status = status
    }

    public var description: String {
        status.map { "\(reason.rawValue) (HTTP \($0))" } ?? reason.rawValue
    }
}
