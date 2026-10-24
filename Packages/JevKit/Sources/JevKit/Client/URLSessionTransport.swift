// Packages/JevKit/Sources/JevKit/Client/URLSessionTransport.swift
import Foundation

/// The only code in the fork that opens a network connection
/// (`NetworkSourceScanTests` fails on any other). It reaches only
/// `https://api.typesafe.ai/v1/...`.
///
/// - Ephemeral session: no URL cache, cookie store, or credential store, so
///   nothing about a request is kept on disk.
/// - No waiting for connectivity: no network fails at once.
/// - Redirects are refused, so the Authorization header never goes to
///   another URL.
/// - The response body is read as a stream and refused past 1 MiB.
/// - App Transport Security defaults apply: TLS 1.2 or later and system
///   certificate checks. No pinning (see the Jev base spec).
public final class URLSessionTransport: JevTransport {
    public static let maxResponseBytes = 1 << 20

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration, delegate: RedirectRefuser(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest, timeout: Duration) async throws -> JevHTTPResponse {
        guard Self.isAllowedDestination(request.url) else { throw JevError(.badRequest) }
        var request = request
        request.timeoutInterval = max(Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18, 0.05)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw Self.map(error)
        }
        guard let http = response as? HTTPURLResponse, Self.isAllowedDestination(http.url) else {
            throw JevError(.invalidResponse)
        }
        if http.expectedContentLength > Self.maxResponseBytes {
            throw JevError(.invalidResponse, status: http.statusCode)
        }

        var body = Data()
        do {
            for try await byte in bytes {
                body.append(byte)
                if body.count > Self.maxResponseBytes {
                    throw JevError(.invalidResponse, status: http.statusCode)
                }
            }
        } catch let error as JevError {
            throw error
        } catch {
            throw Self.map(error)
        }

        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String {
                headers[name.lowercased()] = value
            }
        }
        return JevHTTPResponse(status: http.statusCode, headers: headers, body: body)
    }

    /// Maps a URLSession error to a reason that holds no URL or body.
    static func map(_ error: Error) -> JevError {
        guard let urlError = error as? URLError else {
            return error is CancellationError ? JevError(.timeout) : JevError(.offline)
        }
        switch urlError.code {
        case .timedOut, .cancelled:
            // The runner cancels a request only when the capture's budget ends.
            return JevError(.timeout)
        case .networkConnectionLost:
            // Worth one retry: the server may have closed an idle connection.
            return JevError(.server)
        default:
            // No network, host not found, TLS failure, and the rest.
            return JevError(.offline)
        }
    }
}

/// Refuses every redirect. The task then gets the 3xx response itself, which
/// the client reports as an invalid response.
private final class RedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
