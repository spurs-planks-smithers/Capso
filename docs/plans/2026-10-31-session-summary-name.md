# Plan: on-device summary for the session name (#200)

Date: 2026-10-31. Branch: `claude/summary-name-ondevice-534d42`. Issue: #200. Related: #198 (the first line), #164 (the old "no model" rule). Decision: `docs/decisions/2026-10-31-session-summary-name.md`.

## Hold rule

The base of this pull request is `claude/magical-jones-ab0ded`, the branch of draft PR 199 (#198). That PR is held until release 0.6.0 ships. This PR stays a draft too. After #199 merges, change the base to `main`, rebase, rerun the checks, and only then mark it ready.

## Behavior (Drew, 2026-10-31: "Yes, separate PR")

- `<name>` in `Session Name: <app> - <name>` becomes one short name that summarizes all captures of a round, or all checked captures of a selection. It comes from Apple's on-device model.
- The input is the reviewer's words only: badge instructions and capture notes. No OCR text and no window titles.
- The model runs on the Mac and sends nothing out. A Mac without macOS 26, or with Apple Intelligence off, keeps today's name (`RoundTitle`).
- A copy never waits for the model. A missing name falls back to today's name.
- The Recent Rounds menu title does not change.
- New flag `sessionSummary`, off in both channels, not a Jev flag. It runs only with `sessionTitle` on as well.

## Calls I make

1. **Storage:** one file, `.summary-names.json`, in the rounds folder. Not a field in `feedback.json`. Why: a selection spans rounds, so a round field cannot hold its name. A round field also needs a staleness check, and an older copy of the app would drop it on its next write. No `schemaVersion` change.
2. **Key:** a 64-bit FNV-1a hash of the revision and the reviewer's words (`SummaryNames.basis`). The same words give the same key for a round, a capture, a selection, and a zip. A changed note or a new capture gives a new key, so a name never goes stale.
3. **Request rule:** at most one request per key at a time. A key that gave no name is not asked again until a relaunch. Fewer than three words in all: no request.
4. **When it runs:** when a capture's notes become final (`startJev`'s point), for the capture and for its round. When a capture is checked in the Recent menu, for the selection. On every copy, for a missing name (this covers old rounds).
5. **Wait rule:** no wait anywhere. Jev's round end waits at most 500 ms. The summary does not, because the brief says a copy never waits. A copy right after the last note usually has the cut name. A later copy has the summary.
6. **Fallback:** an unavailable model, a refusal, an error, a vague input (the model answers NONE), or a reply that is not a name all give today's name.
7. **Clean-up:** the reply loses quotes, a period, a label, and Markdown marks. It then goes through `SessionName.safe` and `RoundTitle.shortened` (50 characters). `SessionName` cleans a stored name again before it reaches a prompt.
8. **Instruction:** tuned on 47 local rounds (see the PR). The word "screen" in an early instruction came back as generic names, so the final text bans generic words and allows NONE.
9. **Module split:** FeedbackKit holds only plain values (`SummaryNames`). The model call is `App/Feedback/FeedbackSummaryModel.swift`, gated by `#available(macOS 26, *)`, `SystemLanguageModel.default.availability`, and `canImport(FoundationModels)`. It uses `SystemLanguageModel.default` only. The macOS 27 SDK has a second type, `PrivateCloudComputeLanguageModel`. Never use it here.

## Files

- New: `FeedbackKit/SummaryNames.swift`, `App/Feedback/FeedbackSummaryModel.swift`, `App/Feedback/FeedbackSessionSummary.swift`, the decision record, this plan.
- Edit: `SessionName.swift`, `PromptBuilder.swift`, `ZipText.swift`, `ZipWriter.swift` (a `summaries` value with a default, so existing callers are unchanged), `FeatureFlags.swift`, `scripts/nextshot-flags.sh`, `FeedbackController.swift`, `FeedbackZip.swift`, `RoundTitle.swift` (doc comment), `AGENTS.md`, `docs/agents/bundle-guide.md`.
- No `CHANGELOG.md` line: with the flag off, a user sees nothing (the #164 precedent).
- No upstream file changes, so no `docs/FORK_NOTES.md` entry. No test is added (Drew's rule for this repository). Tests that the change breaks: none expected.
- Do not bump `VERSION`. Do not release.

## Verify

- `swift test --package-path Packages/FeedbackKit`.
- `swift test -c release -Xswiftc -enable-testing --package-path Packages/JevKit` (includes `NetworkSourceScanTests`).
- App Debug build and `CapsoTests` (see `AGENTS.md`).
- The built app links FoundationModels weakly (`otool -l`), so macOS 15 still launches it.
- A throwaway probe outside the repository runs the model on the real note sets and shows names next to today's names, with latency.
- No live install. Drew's Nextshot Dev keeps running. The live steps stay unverified in the PR.
