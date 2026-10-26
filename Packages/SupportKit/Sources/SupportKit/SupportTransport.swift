import CryptoKit
import Foundation

public struct SupportReceipt: Codable, Sendable, Equatable {
    public let id: String
    public let status: String
}

/// No cookies, redirects, stored credentials, or background retries.
public final class SupportTransport: Sendable {
    public init() {}

    private struct FileDescription: Encodable { let name: String; let bytes: Int; let sha256: String; let contentType: String }
    private struct ReservationRequest: Encodable {
        let source = "native"
        let category = "other"
        let message: String
        let contactEmail: String?
        let idempotencyKey: String
        let files: [FileDescription]
    }
    private struct Upload: Decodable { let id: String }
    private struct Reservation: Decodable { let id: String; let token: String; let uploads: [Upload] }

    public func submit(_ package: SupportPackage) async throws -> SupportReceipt {
        try Task.checkCancellation()
        let bytes = try Data(contentsOf: package.url, options: .mappedIfSafe)
        guard bytes.count == package.bytes, bytes.count <= SupportLimits.uploadBytes,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == package.sha256 else { throw SupportError.invalidInput }
        let request = ReservationRequest(message: package.note, contactEmail: package.contactEmail, idempotencyKey: package.idempotencyKey, files: [FileDescription(name: "support.zip", bytes: bytes.count, sha256: package.sha256, contentType: "application/zip")])
        let reservationData = try await send(path: "/v1/reservations", method: "POST", token: nil, body: JSONEncoder().encode(request), contentType: "application/json")
        let reservation: Reservation
        do { reservation = try JSONDecoder().decode(Reservation.self, from: reservationData) }
        catch { throw SupportError.invalidResponse }
        guard Self.validIdentifier(reservation.id), reservation.token.utf8.count <= 256,
              !reservation.token.isEmpty, reservation.token.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 32 && $0.value < 127 }),
              reservation.uploads.count == 1, let upload = reservation.uploads.first, Self.validIdentifier(upload.id) else { throw SupportError.invalidResponse }
        _ = try await send(path: "/v1/submissions/\(reservation.id)/files/\(upload.id)", method: "PUT", token: reservation.token, body: bytes, contentType: "application/zip")
        let completion = try await send(path: "/v1/submissions/\(reservation.id)/complete", method: "POST", token: reservation.token, body: Data(), contentType: "application/json")
        guard let receipt = try? JSONDecoder().decode(SupportReceipt.self, from: completion), receipt.id == reservation.id,
              ["received", "scanning", "screened", "held", "rejected"].contains(receipt.status) else { throw SupportError.invalidResponse }
        return receipt
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 100 && value.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
    }

    private func send(path: String, method: String, token: String?, body: Data, contentType: String) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: try SupportEndpoint.url(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config, delegate: SupportNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.host == "feedback.nextshot.dev" else { throw SupportError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 503 { throw SupportError.serviceUnavailable }
            throw SupportError.requestFailed(http.statusCode)
        }
        guard http.expectedContentLength <= 65_536 else { throw SupportError.invalidResponse }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < 65_536 else { throw SupportError.invalidResponse }
            data.append(byte)
        }
        return data
    }
}

private final class SupportNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
