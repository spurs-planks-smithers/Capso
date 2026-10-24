// Packages/JevKit/Sources/JevKit/Client/JevRetryPolicy.swift
import Foundation

/// When and how long to wait before a retry.
///
/// Backoff uses "full jitter" from the AWS Architecture Blog ("Exponential
/// Backoff and Jitter"): a random wait between 0 and the current step. Steps
/// start at `initialBackoff`, double each time, and stop at `maxBackoff`. A
/// `Retry-After` header wins when it asks for a longer wait. The client never
/// starts a wait that would pass the capture's deadline.
public struct JevRetryPolicy: Sendable, Equatable {
    public var maxRetries: Int
    public var initialBackoff: Duration
    public var maxBackoff: Duration

    public init(maxRetries: Int = 2, initialBackoff: Duration = .milliseconds(250), maxBackoff: Duration = .seconds(1)) {
        self.maxRetries = maxRetries
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff
    }

    /// The same set TypeSafe's SDK retries: 408, 429, 529, and 5xx.
    public static let retryStatuses: Set<Int> = [408, 429, 500, 502, 503, 504, 529]

    /// The wait before retry number `attempt + 1`. `random` returns a value
    /// from 0 up to 1.
    public func delay(attempt: Int, retryAfter: Duration?, random: Double) -> Duration {
        var step = initialBackoff
        for _ in 0..<max(attempt, 0) {
            step = min(step * 2, maxBackoff)
        }
        let jittered = step * min(max(random, 0), 1)
        if let retryAfter, retryAfter > jittered {
            return retryAfter
        }
        return jittered
    }

    /// A header value is untrusted. Any wait longer than this is read as this,
    /// so a huge number can never overflow the conversion to whole
    /// milliseconds. Every such wait passes the deadline anyway.
    static let maxRetryAfterMilliseconds = 3_600_000.0

    /// Reads `retry-after-ms` (milliseconds) or `retry-after` (seconds, or
    /// an HTTP date). Header names are lowercased. Nil when absent or bad.
    public static func retryAfter(in headers: [String: String], now: Date = Date()) -> Duration? {
        func clamped(_ milliseconds: Double) -> Duration {
            .milliseconds(Int64(min(max(milliseconds, 0), maxRetryAfterMilliseconds)))
        }
        if let text = headers["retry-after-ms"], let milliseconds = Double(text), milliseconds >= 0, milliseconds.isFinite {
            return clamped(milliseconds)
        }
        guard let text = headers["retry-after"]?.trimmingCharacters(in: .whitespaces) else { return nil }
        if let seconds = Double(text), seconds >= 0, seconds.isFinite {
            return clamped(seconds * 1000)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: text) else { return nil }
        return clamped(date.timeIntervalSince(now) * 1000)
    }
}
