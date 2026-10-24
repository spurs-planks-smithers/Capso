// Packages/JevKit/Sources/JevKit/Client/JevTransport.swift
import Foundation

/// One HTTP response, read in full. Header names are lowercased.
public struct JevHTTPResponse: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        self.body = body
    }
}

/// Sends one HTTP request. `URLSessionTransport` is the real one. Tests use
/// a stub that records requests and returns canned responses.
public protocol JevTransport: Sendable {
    /// Throws `JevError` for a failure without an HTTP response: `.offline`
    /// for no network, `.timeout` when `timeout` passes, `.server` for a
    /// dropped connection, `.invalidResponse` for a body over the size cap.
    func send(_ request: URLRequest, timeout: Duration) async throws -> JevHTTPResponse
}

extension JevTransport {
    /// True only for `https://api.typesafe.ai/v1/...` with no user, password,
    /// or other port. Every transport checks this before it sends.
    public static func isAllowedDestination(_ url: URL?) -> Bool {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host == JevEndpoint.host,
              components.port == nil || components.port == 443,
              components.user == nil,
              components.password == nil
        else { return false }
        return components.path.hasPrefix("/v1/")
    }
}
