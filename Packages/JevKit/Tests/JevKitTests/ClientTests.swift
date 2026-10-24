import FeedbackKit
import Foundation
import ImageIO
import Testing
@testable import JevKit

private let soon: ContinuousClock.Instant = .now + .seconds(30)

private func body(of request: URLRequest) -> String {
    String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
}

@Suite("Client: requests")
struct ClientRequestTests {
    @Test("A text request is JSON with the pinned model, in key order, with no images header")
    func textRequest() async throws {
        let transport = StubTransport([jsonResponse(noulBody("1.1.names_change"))])
        let request = JevRequest(
            state: .fields(["note": .reviewer("make it \"brighter\"\n"), "count": .number(2)]),
            questions: ["1.1.names_change": .noul("Does `note` name a change?", yes: "It names one.")]
        )
        _ = try await makeClient(transport).send(request, deadline: soon)

        let sent = try #require(await transport.requests.first)
        #expect(sent.url == JevEndpoint.systemOneURL)
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(sent.value(forHTTPHeaderField: JevEndpoint.imagesHeader) == nil)
        #expect(body(of: sent) == #"{"model":"jev-1.14.0","state":{"note":"make it \"brighter\"\n","count":2},"questions":{"1.1.names_change":{"type":"noul","instructions":"Does `note` name a change?","criteria":{"true":"It names one."}}}}"#)
    }

    @Test("Choice and Score criteria keep their order")
    func choiceAndScore() async throws {
        let transport = StubTransport([jsonResponse(#"{"model":"jev-1.14.0","answers":{"c":{"type":"choice","choice":"b","confidence":0.8,"probabilities":{"a":0.1,"b":0.9}},"s":{"type":"score","score":1.2,"confidence":0.5,"legend":{},"probabilities":{"0":0.1,"1":0.6,"2":0.3}}},"usage":{"input_tokens":5,"output_tokens":2}}"#)])
        let request = JevRequest(state: "x", questions: [
            "c": .choice("Pick", options: ["a": "first", "b": "second"]),
            "s": .score("Rate", levels: ["low", "mid", "high"]),
        ])
        let result = try await makeClient(transport).send(request, deadline: soon)
        let sent = try #require(await transport.requests.first)
        #expect(body(of: sent).contains(#""c":{"type":"choice","instructions":"Pick","criteria":{"a":"first","b":"second"}}"#))
        #expect(body(of: sent).contains(#""s":{"type":"score","instructions":"Rate","criteria":["low","mid","high"]}"#))
        #expect(result.response.choice("c")?.option == "b")
        #expect(result.response.score("s")?.probabilities == [0.1, 0.6, 0.3])
    }

    @Test("An image request is multipart: the JSON first, then one part per image, with the images header")
    func imageRequest() async throws {
        let image = try preparedImage()
        let transport = StubTransport([jsonResponse(#"{"model":"jev-1.14.0","answers":{"where":{"type":"box","box":{"top":0.1,"bottom":0.5,"left":0.2,"right":0.6},"confidence":null}},"usage":{"input_tokens":300,"output_tokens":20}}"#)])
        let request = JevRequest(state: .fields(["shot": .image(image)]), questions: ["where": .box("the button in `shot`")])
        let result = try await makeClient(transport).send(request, deadline: soon)

        let sent = try #require(await transport.requests.first)
        let contentType = try #require(sent.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary=nextshot-"))
        #expect(sent.value(forHTTPHeaderField: JevEndpoint.imagesHeader) == "true")

        let reference = "nshot-img-\(image.id.uuidString.lowercased())"
        let raw = try #require(sent.httpBody)
        let text = String(decoding: raw, as: UTF8.self)
        let requestPart = try #require(text.range(of: #"name="request""#))
        let imagePart = try #require(text.range(of: #"name="image-1"; filename="image-1.png""#))
        #expect(requestPart.lowerBound < imagePart.lowerBound)
        #expect(text.contains(#""state":{"shot":"\#(reference)"}"#))
        #expect(text.contains(#""assets":{"\#(reference)":{"type":"image","part":"image-1"}}"#))
        #expect(raw.range(of: image.png) != nil)
        #expect(result.response.box("where")?.confidence == nil)
    }

    @Test("A request that fails a check is never sent")
    func badRequestsAreNotSent() async throws {
        let transport = StubTransport()
        let client = makeClient(transport)
        let bad: [JevRequest] = [
            JevRequest(state: "x", questions: [(id: JevCodeText, question: JevQuestion)]()),
            JevRequest(state: "x", questions: ["has space": .noul("?")]),
            JevRequest(state: "x", questions: ["where": .box("the button")]),
            JevRequest(state: "x", questions: ["s": .score("?", levels: [])]),
            JevRequest(state: "x", questions: ["c": .choice("?", options: ["": "empty"])]),
            JevRequest(state: .number(.nan), questions: ["q": .noul("?")]),
        ]
        for request in bad {
            await #expect(throws: JevError(.badRequest)) {
                _ = try await client.send(request, deadline: soon)
            }
        }
        #expect(await transport.count == 0)
    }
}

@Suite("Client: host guard")
struct HostGuardTests {
    @Test("Only https://api.typesafe.ai/v1/... is allowed")
    func destinations() {
        #expect(URLSessionTransport.isAllowedDestination(JevEndpoint.systemOneURL))
        for text in [
            "http://api.typesafe.ai/v1/systemone",
            "https://api.typesafe.ai.evil.example/v1/systemone",
            "https://evil.example/v1/systemone",
            "https://api.typesafe.ai:8443/v1/systemone",
            "https://user:pass@api.typesafe.ai/v1/systemone",
            "https://api.typesafe.ai/admin",
        ] {
            #expect(!URLSessionTransport.isAllowedDestination(URL(string: text)), "\(text) was allowed")
        }
    }

    @Test("The real transport refuses another host before it connects")
    func transportRefuses() async {
        let transport = URLSessionTransport()
        let request = URLRequest(url: URL(string: "https://example.com/v1/systemone")!)
        await #expect(throws: JevError(.badRequest)) {
            _ = try await transport.send(request, timeout: .seconds(1))
        }
    }
}

@Suite("Client: answer checks")
struct AnswerCheckTests {
    private func send(_ json: String, _ questions: KeyValuePairs<JevCodeText, JevQuestion>, contentType: String = "application/json") async throws -> JevResponse {
        let transport = StubTransport([.success(JevHTTPResponse(status: 200, headers: ["Content-Type": contentType], body: Data(json.utf8)))])
        return try await makeClient(transport).send(JevRequest(state: "x", questions: questions), deadline: soon).response
    }

    @Test("A valid answer of each type is accepted")
    func validAnswers() async throws {
        let response = try await send(noulBody("q", probability: 0.25), ["q": .noul("?")])
        #expect(response.noul("q") == 0.25)
        #expect(response.inputTokens == 12)
    }

    @Test("Each broken answer rejects the whole response")
    func invalidAnswers() async {
        let usage = #""usage":{"input_tokens":1,"output_tokens":1}"#
        let cases: [(String, KeyValuePairs<JevCodeText, JevQuestion>, JevFailureReason)] = [
            (noulBody("q", probability: 1.5), ["q": .noul("?")], .invalidResponse),
            (noulBody("other"), ["q": .noul("?")], .invalidResponse),
            (#"{"model":"jev-1.14.0","answers":{"q":{"type":"noul","noul":0.5},"extra":{"type":"noul","noul":0.5}},\#(usage)}"#, ["q": .noul("?")], .invalidResponse),
            (#"{"model":"jev-1.14.0","answers":{"q":{"type":"choice","choice":"a","confidence":0.9,"probabilities":{"a":0.9,"b":0.1}}},\#(usage)}"#, ["q": .noul("?")], .invalidResponse),
            (#"{"model":"jev-1.14.0","answers":{"q":{"type":"choice","choice":"z","confidence":0.9,"probabilities":{"a":0.9,"b":0.1}}},\#(usage)}"#, ["q": .choice("?", options: ["a": "", "b": ""])], .invalidResponse),
            (#"{"model":"jev-1.14.0","answers":{"q":{"type":"choice","choice":"a","confidence":0.9,"probabilities":{"a":0.5,"b":0.1}}},\#(usage)}"#, ["q": .choice("?", options: ["a": "", "b": ""])], .invalidResponse),
            (#"{"model":"jev-1.14.0","answers":{"q":{"type":"score","score":3.5,"confidence":0.9,"probabilities":{"0":0.5,"1":0.5}}},\#(usage)}"#, ["q": .score("?", levels: ["a", "b"])], .invalidResponse),
            (#"{"model":"jev-1.14.0","answers":{"q":{"type":"score","score":0.5,"confidence":0.9,"probabilities":{"0":0.5,"2":0.5}}},\#(usage)}"#, ["q": .score("?", levels: ["a", "b"])], .invalidResponse),
            (#"{"model":"jev-1.14.0","answers":{"q":{"type":"noul","noul":0.5}},"usage":{"input_tokens":-1,"output_tokens":1}}"#, ["q": .noul("?")], .invalidResponse),
            (#"not json"#, ["q": .noul("?")], .invalidResponse),
            (noulBody("q", model: "jev-1.15.0"), ["q": .noul("?")], .modelMismatch),
        ]
        for (json, questions, reason) in cases {
            await #expect(throws: JevError(reason, status: 200), "\(json)") {
                _ = try await send(json, questions)
            }
        }
    }

    @Test("A Box with top past bottom, or an edge outside 0 to 1, is rejected")
    func invalidBoxes() async throws {
        let image = try preparedImage()
        for box in [#"{"top":0.6,"bottom":0.5,"left":0.1,"right":0.2}"#, #"{"top":0.1,"bottom":0.5,"left":-0.1,"right":0.2}"#] {
            let transport = StubTransport([jsonResponse(#"{"model":"jev-1.14.0","answers":{"b":{"type":"box","box":\#(box),"confidence":0.4}},"usage":{"input_tokens":1,"output_tokens":1}}"#)])
            let request = JevRequest(state: .image(image), questions: ["b": .box("it")])
            await #expect(throws: JevError(.invalidResponse, status: 200)) {
                _ = try await makeClient(transport).send(request, deadline: soon)
            }
        }
    }

    @Test("A body that is not JSON by its content type is rejected")
    func wrongContentType() async {
        await #expect(throws: JevError(.invalidResponse, status: 200)) {
            _ = try await send(noulBody(), ["q": .noul("?")], contentType: "text/html")
        }
    }
}

@Suite("Client: retries and keys")
struct RetryTests {
    private let request = JevRequest(state: "x", questions: ["q": .noul("?")])

    @Test("429, then 200, succeeds after one retry")
    func retriesRateLimit() async throws {
        let transport = StubTransport([status(429), jsonResponse(noulBody())])
        let result = try await makeClient(transport).send(request, deadline: soon)
        #expect(result.retries == 1)
        #expect(await transport.count == 2)
    }

    @Test("529 and 503 are retried, at most twice")
    func retriesAtMostTwice() async {
        let transport = StubTransport([status(529), status(503), status(529), jsonResponse(noulBody())])
        await #expect(throws: JevError(.overloaded, status: 529)) {
            _ = try await makeClient(transport).send(request, deadline: soon)
        }
        #expect(await transport.count == 3)
    }

    @Test("400, 401, 422, and offline are never retried")
    func finalFailures() async {
        for (result, reason) in [(status(400), JevFailureReason.badRequest), (status(401), .unauthorized), (status(422), .badRequest), (.failure(JevError(.offline)), .offline)] as [(Result<JevHTTPResponse, JevError>, JevFailureReason)] {
            let transport = StubTransport([result, jsonResponse(noulBody())])
            do {
                _ = try await makeClient(transport).send(request, deadline: soon)
                Issue.record("\(reason) succeeded")
            } catch let error as JevError {
                #expect(error.reason == reason)
            } catch {
                Issue.record("unexpected \(error)")
            }
            #expect(await transport.count == 1, "\(reason) was retried")
        }
    }

    @Test("A Retry-After past the deadline is not waited for")
    func retryAfterPastDeadline() async {
        let transport = StubTransport([status(429, headers: ["Retry-After": "30"]), jsonResponse(noulBody())])
        await #expect(throws: JevError(.rateLimited, status: 429)) {
            _ = try await makeClient(transport).send(request, deadline: .now + .seconds(2))
        }
        #expect(await transport.count == 1)
    }

    @Test("Backoff doubles from 250 ms, stops at 1 s, and takes a longer Retry-After")
    func backoff() {
        let policy = JevRetryPolicy()
        #expect(policy.delay(attempt: 0, retryAfter: nil, random: 1) == .milliseconds(250))
        #expect(policy.delay(attempt: 1, retryAfter: nil, random: 1) == .milliseconds(500))
        #expect(policy.delay(attempt: 5, retryAfter: nil, random: 1) == .seconds(1))
        #expect(policy.delay(attempt: 0, retryAfter: nil, random: 0) == .zero)
        #expect(policy.delay(attempt: 0, retryAfter: .seconds(3), random: 1) == .seconds(3))
        #expect(JevRetryPolicy.retryAfter(in: ["retry-after": "2"]) == .seconds(2))
        #expect(JevRetryPolicy.retryAfter(in: ["retry-after-ms": "150"]) == .milliseconds(150))
        #expect(JevRetryPolicy.retryAfter(in: ["retry-after": "soon"]) == nil)
    }

    @Test("A huge Retry-After value is clamped to one hour and never crashes")
    func hugeRetryAfter() {
        #expect(JevRetryPolicy.retryAfter(in: ["retry-after-ms": "1e30"]) == .seconds(3600))
        #expect(JevRetryPolicy.retryAfter(in: ["retry-after": "1e300"]) == .seconds(3600))
        #expect(JevRetryPolicy.retryAfter(in: ["retry-after": "Fri, 31 Dec 9999 23:59:59 GMT"]) == .seconds(3600))
        #expect(JevRetryPolicy.retryAfter(in: ["retry-after": "Mon, 01 Jan 2001 00:00:00 GMT"]) == .zero)
    }

    @Test("No key, or a key with a line break, sends nothing")
    func noKey() async {
        for key in [nil, "", "abc\r\nX-Evil: 1", "with space"] as [String?] {
            let transport = StubTransport([jsonResponse(noulBody())])
            await #expect(throws: JevError(.noKey)) {
                _ = try await makeClient(transport, key: StubKeyProvider(key)).send(request, deadline: soon)
            }
            #expect(await transport.count == 0)
        }
    }

    @Test("A missing key is looked for again at most once per 5 minutes")
    func missingKeyRecheck() async {
        let key = StubKeyProvider(nil)
        let client = makeClient(StubTransport(), key: key)
        _ = await client.hasKey()
        _ = await client.hasKey()
        #expect(await key.reads == 1)
    }

    @Test("An error never holds the key")
    func errorsHoldNoKey() async {
        let transport = StubTransport([status(401)])
        do {
            _ = try await makeClient(transport).send(request, deadline: soon)
        } catch {
            #expect(!String(describing: error).contains("test-key-123"))
            #expect(!String(reflecting: error).contains("test-key-123"))
        }
    }
}

@Suite("Image preparation")
struct ImagePreparationTests {
    @Test("Every result has both sides from 280 to 1568 pixels")
    func sizes() throws {
        let cases: [(Int, Int, Int, Int)] = [
            (50, 50, 280, 280),
            (3000, 2000, 1568, 1045),
            (2000, 100, 1568, 280),
            (100, 2000, 280, 1568),
            (800, 600, 800, 600),
        ]
        for (width, height, expectedWidth, expectedHeight) in cases {
            let image = try JevImagePreparation.prepare(blankImage(width: width, height: height), sourceRegion: FeedbackBox(x1: 0, y1: 0, x2: width, y2: height))
            #expect(image.size == PixelSize(width: expectedWidth, height: expectedHeight), "\(width)x\(height)")
            let source = try #require(CGImageSourceCreateWithData(image.png as CFData, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(decoded.width == expectedWidth && decoded.height == expectedHeight)
        }
    }

    @Test("A very wide region is padded, and its Box maps back to the region")
    func paddingMaps() throws {
        let image = try JevImagePreparation.prepare(blankImage(width: 2000, height: 100), sourceRegion: FeedbackBox(x1: 10, y1: 20, x2: 2010, y2: 120))
        #expect(image.contentRect.y1 > 0)
        let whole = image.sourceBox(for: JevBox(
            top: Double(image.contentRect.y1) / Double(image.size.height),
            bottom: Double(image.contentRect.y2) / Double(image.size.height),
            left: 0,
            right: 1
        ))
        #expect(whole == FeedbackBox(x1: 10, y1: 20, x2: 2010, y2: 120))
    }

    @Test("The bundle loader crops a region of the capture file")
    func bundleLoader() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("jevkit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let capture = sampleCapture()
        try JevImagePreparation.pngData(blankImage(width: 800, height: 600))!.write(to: folder.appendingPathComponent(capture.imageFile))
        let round = FeedbackRound(name: "f", slug: "f", folderName: "f", startedAt: Date(), captures: [capture])

        let image = try JevImageLoader.bundle(folderURL: folder, round: round).image(of: 1, region: FeedbackBox(x1: 700, y1: 500, x2: 900, y2: 700))
        #expect(image.sourceRegion == FeedbackBox(x1: 700, y1: 500, x2: 800, y2: 600))
        #expect(image.size == PixelSize(width: 280, height: 280))
        #expect(throws: JevError(.jobError)) {
            _ = try JevImageLoader.bundle(folderURL: folder, round: round).image(of: 1, .clean)
        }
    }
}
