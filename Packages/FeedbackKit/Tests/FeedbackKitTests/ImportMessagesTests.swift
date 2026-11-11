import Foundation
import Testing
@testable import FeedbackKit

/// The import's toasts (#87).
@Suite("Import text")
struct ImportMessagesTests {
    @Test("The ready toast names the round and counts its captures")
    func readyToast() {
        #expect(ImportMessages.ready(name: "Pricing page", captureCount: 3)
            == "Imported \u{201C}Pricing page\u{201D}, 3 captures.\nIt lists under All Rounds. Copy its prompt, or zip it again to share.")
        // Singular reads as one capture, not "1 captures".
        #expect(ImportMessages.ready(name: "Pricing page", captureCount: 1).hasPrefix("Imported \u{201C}Pricing page\u{201D}, 1 capture."))
        #expect(ImportMessages.ready(name: "Pricing page", captureCount: 0).contains("0 captures"))
    }

    @Test("A failure names the reason and never the folder, which holds the round name")
    func failureToast() {
        #expect(ImportMessages.failure(for: FeedbackRoundStore.StoreError.roundNotFound("secret-folder-name"))
            == "Nothing imported.\nPick the folder that holds feedback.json, not the zip itself.")
        #expect(ImportMessages.failure(for: FeedbackRoundStore.StoreError.roundWasImported("secret-folder-name"))
            == "Nothing imported.\nThat round was already imported.")

        // Anything else, including a decode error, gets the neutral line.
        let other = NSError(domain: "test", code: 1)
        #expect(ImportMessages.failure(for: other) == "Nothing imported.\nThe folder could not be read as a Nextshot round.")

        let failures: [Error] = [
            FeedbackRoundStore.StoreError.roundNotFound("secret-folder-name"),
            FeedbackRoundStore.StoreError.roundWasImported("secret-folder-name"),
            other,
        ]
        for error in failures {
            #expect(!ImportMessages.failure(for: error).contains("secret"))
        }
    }
}
