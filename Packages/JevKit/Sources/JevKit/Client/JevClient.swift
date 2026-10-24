// Packages/JevKit/Sources/JevKit/Client/JevClient.swift
import Foundation

/// One request's result, with what jev.json records about it.
public struct JevSendResult: Sendable, Equatable {
    public var response: JevResponse
    public var retries: Int
}

/// Sends Jev requests to TypeSafe: `POST /v1/systemone` with the pinned
/// model, retries inside the capture's deadline, and a full check of every
/// answer. Jev's answers are untrusted data, so one failed check rejects the
/// whole response.
public actor JevClient {
    private let transport: any JevTransport
    private let keyProvider: any JevKeyProvider
    private let policy: JevRetryPolicy
    private let random: @Sendable () -> Double
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The key, once read. It lives only here, in memory, for the app run.
    private var key: String?
    private var lastMissingKeyCheck: ContinuousClock.Instant?
    /// A missing key is looked for again at most this often, so a key stored
    /// later works without a relaunch and the Keychain is not read per capture.
    static let missingKeyRecheck: Duration = .seconds(300)

    public init(
        transport: any JevTransport,
        keyProvider: any JevKeyProvider,
        policy: JevRetryPolicy = JevRetryPolicy(),
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.transport = transport
        self.keyProvider = keyProvider
        self.policy = policy
        self.random = random
        self.sleep = sleep
    }

    /// True when a usable key is in memory, after one read if needed.
    public func hasKey() async -> Bool {
        await currentKey() != nil
    }

    private func currentKey() async -> String? {
        if let key { return key }
        let now = ContinuousClock.now
        if let last = lastMissingKeyCheck, now - last < Self.missingKeyRecheck {
            return nil
        }
        lastMissingKeyCheck = now
        guard let read = await keyProvider.key(), JevKey.isUsable(read) else { return nil }
        key = read
        return read
    }

    /// Sends one request. Throws `JevError` only.
    public func send(_ request: JevRequest, deadline: ContinuousClock.Instant) async throws -> JevSendResult {
        let encoded = try JevRequestEncoder.encode(request)
        guard let key = await currentKey() else { throw JevError(.noKey) }

        var urlRequest = URLRequest(url: JevEndpoint.systemOneURL)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = encoded.body
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(encoded.contentType, forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if encoded.needsImagesHeader {
            urlRequest.setValue("true", forHTTPHeaderField: JevEndpoint.imagesHeader)
        }

        var retries = 0
        while true {
            if Task.isCancelled { throw JevError(.timeout) }
            let remaining = deadline - .now
            guard remaining > .zero else { throw JevError(.timeout) }

            let failure: JevError
            var retryAfter: Duration?
            do {
                let response = try await transport.send(urlRequest, timeout: min(remaining, .seconds(2)))
                if response.status == 200 {
                    return JevSendResult(response: try JevResponseDecoder.decode(response, for: request), retries: retries)
                }
                failure = JevError.forStatus(response.status)
                retryAfter = JevRetryPolicy.retryAfter(in: response.headers)
            } catch let error as JevError {
                failure = error
            } catch {
                failure = JevError(.offline)
            }

            guard failure.isRetryable, retries < policy.maxRetries else { throw failure }
            let wait = policy.delay(attempt: retries, retryAfter: retryAfter, random: random())
            // A wait that would pass the deadline is never started.
            guard ContinuousClock.now + wait < deadline else { throw failure }
            do {
                try await sleep(wait)
            } catch {
                throw JevError(.timeout)
            }
            retries += 1
        }
    }
}

/// Reads and checks a 200 response against the request that was sent.
enum JevResponseDecoder {
    /// Probabilities may round. A sum outside this range is not a distribution.
    static let probabilitySum: ClosedRange<Double> = 0.95...1.05

    private struct RawResponse: Decodable {
        var model: String
        var answers: [String: RawAnswer]
        var usage: RawUsage
    }

    private struct RawUsage: Decodable {
        var input_tokens: Int
        var output_tokens: Int
    }

    private struct RawAnswer: Decodable {
        var type: String
        var noul: Double?
        var choice: String?
        var score: Double?
        var confidence: Double?
        var probabilities: [String: Double]?
        var box: JevBox?
    }

    static func decode(_ http: JevHTTPResponse, for request: JevRequest) throws -> JevResponse {
        let invalid = JevError(.invalidResponse, status: http.status)
        guard let contentType = http.headers["content-type"], contentType.lowercased().hasPrefix("application/json") else {
            throw invalid
        }
        guard let raw = try? JSONDecoder().decode(RawResponse.self, from: http.body) else { throw invalid }
        guard raw.model == JevEndpoint.model else { throw JevError(.modelMismatch, status: http.status) }
        guard raw.usage.input_tokens >= 0, raw.usage.output_tokens >= 0 else { throw invalid }
        guard Set(raw.answers.keys) == Set(request.questions.map(\.id)) else { throw invalid }

        var answers: [String: JevAnswer] = [:]
        for entry in request.questions {
            guard let answer = raw.answers[entry.id], let checked = check(answer, against: entry.question) else { throw invalid }
            answers[entry.id] = checked
        }
        return JevResponse(
            model: raw.model,
            answers: answers,
            inputTokens: raw.usage.input_tokens,
            outputTokens: raw.usage.output_tokens,
            requestID: http.headers[JevEndpoint.requestIDHeader]
        )
    }

    private static func check(_ raw: RawAnswer, against question: JevQuestion) -> JevAnswer? {
        func unit(_ value: Double?) -> Double? {
            guard let value, value.isFinite, (0...1).contains(value) else { return nil }
            return value
        }

        switch question.kind {
        case .noul:
            guard raw.type == "noul", let probability = unit(raw.noul) else { return nil }
            return .noul(probability)

        case .choice(let options):
            guard raw.type == "choice",
                  let option = raw.choice,
                  let confidence = unit(raw.confidence),
                  let probabilities = raw.probabilities,
                  Set(probabilities.keys) == Set(options.map(\.name)),
                  probabilities.keys.contains(option),
                  probabilities.values.allSatisfy({ unit($0) != nil }),
                  probabilitySum.contains(probabilities.values.reduce(0, +))
            else { return nil }
            return .choice(JevChoiceAnswer(option: option, confidence: confidence, probabilities: probabilities))

        case .score(let levels):
            guard raw.type == "score",
                  let score = raw.score, score.isFinite, (0...Double(levels.count - 1)).contains(score),
                  let confidence = unit(raw.confidence),
                  let probabilities = raw.probabilities,
                  Set(probabilities.keys) == Set((0..<levels.count).map(String.init))
            else { return nil }
            let ordered = (0..<levels.count).compactMap { unit(probabilities[String($0)]) }
            guard ordered.count == levels.count, probabilitySum.contains(ordered.reduce(0, +)) else { return nil }
            return .score(JevScoreAnswer(score: score, confidence: confidence, probabilities: ordered))

        case .box:
            guard raw.type == "box", let box = raw.box,
                  [box.top, box.bottom, box.left, box.right].allSatisfy({ unit($0) != nil }),
                  box.top < box.bottom, box.left < box.right
            else { return nil }
            if let confidence = raw.confidence {
                guard unit(confidence) != nil else { return nil }
            }
            return .box(JevBoxAnswer(box: box, confidence: raw.confidence))
        }
    }
}
