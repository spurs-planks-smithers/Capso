# Session summary name, October 31, 2026

Issue 200. Drew approved it on 2026-10-31 ("Yes, separate PR"). It builds on the session name line of issue 198.

### Decision

The `<name>` in the first line `Session Name: <app> - <name>` becomes a summary of all captures, written by Apple's on-device model. The model reads the reviewer's words only. It runs on the Mac and sends nothing out. A Mac without macOS 26, or with Apple Intelligence off, keeps the name that `RoundTitle` cuts from the first answer.

### What this reverses

Issue 164 (2026-10-28) kept round titles in plain code: "no model and no network". That rule stays for the Recent Rounds menu title and for every other title. This record lifts it for the session name line only.

The rule's reason is in the local-only section of `AGENTS.md`: reviewer words leave the Mac only through two named paths, JevKit and SupportKit. The on-device model opens no connection and adds no path. The cut name names the first item only, so a round with several captures gets a name that covers one of them. That is the gap this change closes.

### The model

- Use `SystemLanguageModel.default` and nothing else. The macOS 27 SDK also has `PrivateCloudComputeLanguageModel`, which calls a server. Never use it for this feature. The code file says so.
- Gate every use with `canImport(FoundationModels)`, `#available(macOS 26, *)`, `availability == .available`, and `supportsLocale()`. The project target is macOS 15. The linker marks FoundationModels weak (`LC_LOAD_WEAK_DYLIB`), so macOS 15 still launches the app.
- Greedy sampling, so the same words give the same name.
- Input: `SummaryNames.input(of:)`. One dash line per answer, a blank line between captures, 4,000 characters at most. Fewer than three words in all: no request.
- Output: one noun phrase of two to six words. The model answers NONE for notes that are too short or too vague. Quotes, a closing period, a label, and Markdown marks are removed. The result goes through `SessionName.safe` and `RoundTitle.shortened`, and `SessionName` cleans a stored name again before it reaches a prompt.
- Result on 47 of Drew's own rounds, final instruction, this Mac (macOS 27.0.1, idle): 38 named, 6 got NONE or an unusable reply, 3 skipped for having fewer than three words, 0 errors or refusals. Latency over the 44 requests: median 0.36 s, longest 0.72 s. A busy Mac was slower: an early instruction took up to 1.77 s once.

### Where the name is stored

One file, `.summary-names.json`, in the rounds folder. Each entry is a key and a name. The key is a hash of the instruction text and the reviewer's words. Edit the instruction and every old name stops matching, with no number to remember.

I did not add a field to `feedback.json`:

| Question | Round field | Names file |
|---|---|---|
| Does a selection get a name? | No. A selection spans rounds. | Yes. The key comes from the words. |
| Can a name go stale? | Yes. A new capture or a changed note needs a check. | No. New words give a new key. |
| What does an older copy of the app do? | It drops the field on its next write. | It never reads the file. |
| Does `schemaVersion` change? | A bump hides the round from older copies. No bump loses the field. | No change. |

The file keeps the newest 1,000 names. A file that is missing, unreadable, or from a newer format reads as empty. The Dev app and the production app share the folder, so they share the file. The last writer wins, and a lost name returns on the next copy.

### When it runs, and what a copy does

- A copy never waits. Jev's round end waits at most 500 ms. The summary has no wait.
- A capture's notes become final: the capture and its round start a request in the background.
- A capture is checked in the Recent menu: the selection starts a request after 0.8 s with no further click, so five quick checks start one request.
- A NONE answer or a reply that is not a name is not asked again until a relaunch. An error, such as a rate limit, is asked again after 60 s.
- Every copy starts a request for a missing name and uses the cut name now. This covers rounds made before the flag.
- A capture prompt copied right after the last note usually has the cut name. The model needs 0.4 to 0.9 s. Copy Last Capture Prompt, and the round prompt, have the summary a moment later.
- A name can differ between two pastes of one round: the first used the cut name, the second used the summary. That is the cost of never waiting.

### Flag

`sessionSummary` started off in both channels. On 2026-11-01 Drew tested Dev build 899 ("worked awesome") and turned it on in both channels for release 0.6.0. This replaces the off default above. It is not a Jev flag and not dev-only. The summary runs only when `sessionTitle` is on as well. Turn it off on one Mac with `scripts/nextshot-flags.sh set sessionSummary off`. Issue 198 said its change must not ship in 0.6.0 (2026-10-31). Drew's message of 2026-11-01 replaces that ruling, because the summary builds on the session name line.

The `releasedInBuild` number in `FeatureFlags.swift` is a guess at the release commit's build. Nothing reads it at run time. Check it when the release is cut.

### Not changed

- The files on disk (`prompt.md`, `<stem>-prompt.md`) never carry a session name.
- The Recent Rounds menu title.
- No upload, no TypeSafe call, no new permission.
- `CHANGELOG.md` got a line on 2026-11-01, because the flag is now on.

### Research before the default-on change (2026-11-01)

The memo `docs/research/2026-11-01-on-device-summary-availability.md` covers requirements, reach, and risks. Reach is a range with Low confidence: the summary should appear on 30% to 65% of all Macs and on 50% to 80% of Nextshot's audience. No public source measures it. It found one code gap, which this change closes: a guardrail violation, an unsupported language, a refusal, or an input that is too long used to count as a failure and was asked again after 60 seconds on every copy. It now counts as no name.

Still open from the memo: nobody ran the notarized production DMG with the model. m5pro may not run production Nextshot, so the check needs another approved Mac. The scan rule for `PrivateCloudComputeLanguageModel` waits for Drew's approval, because his rule for this repository adds no test unprompted.

### Open

- The instruction was tuned on 47 of Drew's own rounds. Vague notes get no summary, and a few clear sets do too ("Always call this page ..."). The cut name covers them.
- A scan rule for `PrivateCloudComputeLanguageModel` in `NetworkSourceScanTests` would enforce the model choice. Drew's rule for this repository adds no test unprompted, so it is not in this change.
