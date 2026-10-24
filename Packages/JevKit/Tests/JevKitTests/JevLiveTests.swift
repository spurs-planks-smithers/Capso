import Foundation
import Testing
@testable import JevKit

/// The one test that calls TypeSafe. It runs only with NEXTSHOT_JEV_LIVE=1
/// and a key in TYPESAFE_API_KEY, through `scripts/jev-live-test.sh`. It
/// sends made-up text only: no capture, note, or screen text.
@Suite("Live TypeSafe check", .enabled(if: ProcessInfo.processInfo.environment["NEXTSHOT_JEV_LIVE"] == "1"))
struct JevLiveTests {
    struct EnvironmentKey: JevKeyProvider {
        func key() async -> String? {
            ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"]
        }
    }

    @Test("One text-only request returns checked answers from the pinned model")
    func liveRequest() async throws {
        let client = JevClient(transport: URLSessionTransport(), keyProvider: EnvironmentKey())
        let request = JevRequest(
            state: .fields(["note": .reviewer("Make the Save button blue instead of gray.")]),
            questions: [
                "names_change": .noul("Does `note` ask for a specific change?"),
                "clarity": .score("How clear is the change that `note` asks for?", levels: [
                    "Vague: it names no change.",
                    "Partial: it names a change but not the target or the result.",
                    "Clear: it names the target and the result.",
                ]),
            ]
        )
        let started = ContinuousClock.now
        let result = try await client.send(request, deadline: .now + .seconds(5))
        let elapsed = ContinuousClock.now - started

        #expect(result.response.model == JevEndpoint.model)
        let namesChange = try #require(result.response.noul("names_change"))
        let clarity = try #require(result.response.score("clarity"))
        #expect(namesChange > 0.5)
        #expect(clarity.score > 1)
        #expect(result.response.inputTokens > 0)
        print("live: names_change \(namesChange), clarity \(clarity.score) (confidence \(clarity.confidence)), \(result.response.inputTokens) input tokens, \(elapsed), \(result.retries) retries, request id \(result.response.requestID ?? "none")")
    }
}
