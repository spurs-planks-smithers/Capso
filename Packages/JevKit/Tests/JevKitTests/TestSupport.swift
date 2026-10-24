import CoreGraphics
import FeedbackKit
import Foundation
@testable import JevKit

/// Records every request and answers from a queue. With an empty queue it
/// answers with `fallback`. `delay` makes each answer slow.
actor StubTransport: JevTransport {
    private(set) var requests: [URLRequest] = []
    private var queue: [Result<JevHTTPResponse, JevError>]
    private let fallback: Result<JevHTTPResponse, JevError>
    private let delay: Duration?

    init(_ queue: [Result<JevHTTPResponse, JevError>] = [], fallback: Result<JevHTTPResponse, JevError> = .failure(JevError(.offline)), delay: Duration? = nil) {
        self.queue = queue
        self.fallback = fallback
        self.delay = delay
    }

    func send(_ request: URLRequest, timeout: Duration) async throws -> JevHTTPResponse {
        requests.append(request)
        if let delay {
            try? await Task.sleep(for: min(delay, timeout))
            if delay > timeout { throw JevError(.timeout) }
        }
        let next = queue.isEmpty ? fallback : queue.removeFirst()
        return try next.get()
    }

    var count: Int { requests.count }
}

/// Counts reads, so a test can prove the Keychain was never touched.
actor StubKeyProvider: JevKeyProvider {
    private(set) var reads = 0
    private let value: String?

    init(_ value: String? = "test-key-123") {
        self.value = value
    }

    func key() async -> String? {
        reads += 1
        return value
    }
}

func jsonResponse(_ json: String, status: Int = 200, headers: [String: String] = [:]) -> Result<JevHTTPResponse, JevError> {
    var all = ["Content-Type": "application/json"]
    all.merge(headers) { _, new in new }
    return .success(JevHTTPResponse(status: status, headers: all, body: Data(json.utf8)))
}

func status(_ code: Int, headers: [String: String] = [:]) -> Result<JevHTTPResponse, JevError> {
    jsonResponse(#"{"detail":"x"}"#, status: code, headers: headers)
}

/// A 200 body that answers one Noul named `id`.
func noulBody(_ id: String = "q", probability: Double = 0.9, model: String = JevEndpoint.model) -> String {
    #"{"model":"\#(model)","answers":{"\#(id)":{"type":"noul","noul":\#(probability)}},"usage":{"input_tokens":12,"output_tokens":1}}"#
}

/// A client that never sleeps, so retry tests run at once.
func makeClient(_ transport: StubTransport, key: StubKeyProvider = StubKeyProvider()) -> JevClient {
    JevClient(transport: transport, keyProvider: key, random: { 0.5 }, sleep: { _ in })
}

func blankImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

func preparedImage(width: Int = 400, height: Int = 300) throws -> JevImage {
    try JevImagePreparation.prepare(blankImage(width: width, height: height), sourceRegion: FeedbackBox(x1: 0, y1: 0, x2: width, y2: height))
}
