# Lanes and priority Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Label each item's severity, size, and kind with Jev after its capture, and add an ordered "Order and lanes" section to the end of the copied round prompt when `promptLanes` is on.

**Architecture:** `PromptLanesJob` asks Jev three questions per item (text only) and writes a code-only summary per item to jev.json. At round end, `PromptLanesPlan` reads jev.json and feedback.json and builds a `PromptLanes` value (a FeedbackKit type). `PromptBuilder.render` prints it at the end of the round prompt.

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing (`@Test`, `#expect`), FeedbackKit and JevKit packages, the app's `FeedbackJev` glue.

**Spec:** `docs/superpowers/specs/2026-10-24-prompt-lanes-design.md`. Issues: #71 (Task 1), #72 (Task 2).

## Global Constraints

- Edit only: `Packages/JevKit/Sources/JevKit/Jobs/PromptLanesJob.swift`, new files named below, `PromptBuilder.swift` (one parameter, one append), `App/Feedback/FeedbackJev.swift` (one method), `App/Feedback/FeedbackController.swift` (two call sites). Do not edit the registry, `JevJob.swift`, or the Content, Client, or Runner files.
- With `promptLanes` off, nothing is sent and every prompt is byte-identical to today.
- The request holds reviewer text and code text only: no window title, OCR text, app name, file name, path, or image, even with `jevSendImages` and `jevSendScreenText` on. `requires = []`.
- Every code-text slot is `JevCodeText` from literals and interpolated numbers. A job file must not contain `stringLiteral:`, `stringInterpolation:`, or `JevCodeText(` (a scan test checks this).
- Job id `promptLanes`, version 1, flag `.promptLanes`.
- Lane A: `exact` probability >= 0.8, size level 0 or 1, severity level 0 to 2.
- Order in each lane: severity high to low, then capture index, then badge. Not rated items last in lane B.
- Test fixtures use made-up notes only. The repository is public.
- Docs and comments: Simplified Technical English, no em dash, no italics, American English.
- Run tests: `swift test --package-path Packages/FeedbackKit` and `swift test --package-path Packages/JevKit`. Shell exports NODE_ENV=production; it does not affect Swift.

## Review Focus

- A badge number used by two marks in one capture: the item must appear once, with the first mark's note (job and plan use the same item helper).
- A round resumed after relaunch, or a flag changed mid-round: shadow records from earlier captures still feed the plan; a record with another job version counts as not rated.
- A capture whose job failed or never ran (flag turned on mid-round): its items with notes go to lane B as not rated, and its empty notes still go to Ask first.
- A Score with the wrong number of levels, or a NaN probability: the item is not rated, never lane A.
- A round where every note is empty, or every request failed: no section, the prompt stays byte-identical.

---

### Task 1: The job (issue #71)

**Files:**
- Create: `Packages/FeedbackKit/Sources/FeedbackKit/PromptLanes.swift` (the two level enums only in this task)
- Modify: `Packages/JevKit/Sources/JevKit/Jobs/PromptLanesJob.swift` (the stub)
- Test: `Packages/JevKit/Tests/JevKitTests/PromptLanesJobTests.swift`, `Packages/FeedbackKit/Tests/FeedbackKitTests/PromptLanesTests.swift`

**Interfaces:**
- Produces in FeedbackKit:
  - `public struct PromptLanes: Equatable, Sendable` with nested `public enum Severity: Int, CaseIterable, Sendable { case nit = 0, polish, bug, blocker }` and `public enum Size: Int, CaseIterable, Sendable { case oneLine = 0, oneFile, severalFiles, manyFiles }`. Each has `public var name: String`: "nit", "polish", "bug", "blocker"; "one line", "one file", "several files", "many files". Task 2 adds the rest of the struct.
- Produces in JevKit:
  - `public struct PromptLanesRating: Equatable, Sendable { public var laneA: Bool; public var severity: PromptLanes.Severity; public var size: PromptLanes.Size; public var exact: Double }`
  - `public enum PromptLanesRule` with `public static let exactMinimum = 0.8`, `public static func level(_ answer: JevScoreAnswer?, levels: Int) -> Int?`, and `public static func rate(severity: JevScoreAnswer?, size: JevScoreAnswer?, kind: JevChoiceAnswer?) -> PromptLanesRating?`.
  - `PromptLanesJob.items(in: FeedbackCapture) -> [(badge: Int, note: String)]` (internal static): distinct `capture.badgeNumbers` in ascending order, each with the first mark of that badge that has an instruction, or "". Same logic as `NoteCoachJob.items`.
  - Summary per item, key `"K.N"`: `.fields(["lane": "A" | "B", "severity": <0...3>, "size": <0...3>])` for a rated item, `.fields(["lane": "askFirst"])` for an empty note, `.fields(["lane": "notRated"])` otherwise.

- [ ] **Step 1: Write failing tests** in `PromptLanesJobTests.swift`, using `makeContext(capture:allowed:response:sent:)` and `RequestLog` from `JobInterfaceTests.swift`, and `makeRunner`, `Bundle.make`, `flagSet` from `RunnerTests.swift`:
  - "One request holds each filled note and the general note, and nothing from the screen": capture with badges 1 (note "rename this to Invoice Detail"), 2 (no note), 3 (note "make the cards line up"). Expect 1 request. State fields `general_note` and `items` with entries for 1.1 and 1.3 only. Question ids exactly `["1.1.severity", "1.1.size", "1.1.kind", "1.3.severity", "1.3.size", "1.3.kind"]`. No string in the request equals the window title, OCR text, `imageFile`, or `sourceApp`. Same result with `allowed: [.reviewerText, .screenText, .images]`. `request.kinds == .reviewerText` (code text adds no kind; check `JevDataKinds` if it does) and `request.needsImagesHeader == false`.
  - "When every note is empty, no request is sent, and each item is askFirst".
  - "A capture with no badges sends nothing and returns nothing" (`.empty`).
  - "The output has no refined lines and no files, a summary per item, and a review".
  - "A missing or bad answer makes only its item notRated".
  - "An error from the asker ends the job" (throws).
  - "The job is registered at version 1, with no consent beyond reviewer text".
  - "With promptLanes off, or with jevBase off, nothing is sent" (runner, zero transport calls), and "Shadow records the answers and the summary, and writes no refined file".
- [ ] **Step 2: Write failing rule tests** (`PromptLanesRuleTests` in the same file), each with exact probabilities:
  - severity `[0,0,0.1,0.9]` gives `.blocker`; a tie `[0.5,0.5,0,0]` gives level 1 (higher wins); size tie `[0,0.5,0.5,0]` gives `.severalFiles`.
  - lane A: exact 0.8, size `.oneFile`, severity `.bug` gives `laneA == true`; exact 0.79 gives false; size `.severalFiles` gives false; severity `.blocker` gives false.
  - nil for: a missing answer, a Score with 3 levels, a probability of `.nan` or 1.2, a Choice whose probabilities lack `exact`.
  - `exactMinimum == 0.8`.
- [ ] **Step 3: Write failing name tests** in `PromptLanesTests.swift` (FeedbackKit): every `Severity` and `Size` case maps to the names above.
- [ ] **Step 4: Run both packages' tests.** Expected: the new tests fail to compile or fail.
- [ ] **Step 5: Implement.** In `PromptLanes.swift`, the two enums. In `PromptLanesJob.swift`, the rule, the rating, and `run`. Pattern: `NoteCoachJob.swift`. `level` returns the index of the highest probability, the highest index on a tie, nil when the count differs from `levels` or a value is not finite or outside 0 to 1. `rate` reads `kind.probabilities["exact"]`. Questions (exact text; the accuracy test may change it later and then raises `version`):
  - `K.N.severity`, Score: "How serious is the problem that `items[i].note` describes? `general_note` is context from the same reviewer. Words like \"this\" or \"here\" refer to the marked item." Levels, nit first: "A small taste preference. The screen works and reads well without it. Example: \"maybe a slightly warmer gray\".", "The change improves the look, the wording, or the layout. Nothing is broken. Example: \"make this title bigger\".", "Something is broken, inconsistent, or cut off, but the screen still works. Example: \"the tags are cut off on the right\".", "The feature fails, shows wrong data, or stops the user from finishing a task. Example: \"this total does not match the total on page 2\"."
  - `K.N.size`, Score: "How much code will a developer likely change to do what `items[i].note` asks?" Levels: "One value, word, or sentence in one place. Example: \"rename this column to Voice Minutes\".", "A few related edits in one place, such as one component or one page. Example: \"make these four cards the same width\".", "Edits in a few files or places. Example: \"use the same footnote on page 2 and page 3\".", "A change across the app, the repository, or every page. Example: \"rename this everywhere in the app\"."
  - `K.N.kind`, Choice: "Can a developer do every change in `items[i].note` with no design or product choice?" Options: `exact`: "Every change is exact: new text given in full, a named color, a size or spacing number, or one named element to remove. Example: \"remove the sentence about sources\"." `judgment`: "At least one change needs a choice: make something clearer, better, or consistent, pick a layout, research, explain, or answer a question. A note that names no concrete change, such as \"fix this\", is judgment too."
  - Review line per item: `- K.N: lane A.` (or `lane B.`, `ask first.`, `not rated.`), then for a rated item ` <severity name> <p>, <size name> <p>, exact <p>.` with two decimals, then ` Note: "<note on one line>"`.
- [ ] **Step 6: Run both packages' tests.** Expected: all pass, including `NetworkSourceScanTests` and `registryStubsSendNothing`.
- [ ] **Step 7: Commit** by explicit path: `git add -- Packages/FeedbackKit/Sources/FeedbackKit/PromptLanes.swift Packages/FeedbackKit/Tests/FeedbackKitTests/PromptLanesTests.swift Packages/JevKit/Sources/JevKit/Jobs/PromptLanesJob.swift Packages/JevKit/Tests/JevKitTests/PromptLanesJobTests.swift` then `git commit -m "feat: lanes job rates severity, size, and kind per item (#71)"`.

---

### Task 2: The round plan and the prompt section (issue #72)

**Files:**
- Modify: `Packages/FeedbackKit/Sources/FeedbackKit/PromptLanes.swift`, `Packages/FeedbackKit/Sources/FeedbackKit/PromptBuilder.swift` (`render` only), `App/Feedback/FeedbackJev.swift`, `App/Feedback/FeedbackController.swift:243` and `:520`
- Create: `Packages/JevKit/Sources/JevKit/Jobs/PromptLanesPlan.swift`
- Test: `Packages/FeedbackKit/Tests/FeedbackKitTests/PromptLanesTests.swift`, `Packages/JevKit/Tests/JevKitTests/PromptLanesPlanTests.swift`

**Interfaces:**
- Consumes: Task 1's `PromptLanes.Severity`, `PromptLanes.Size`, `PromptLanesJob.items(in:)`, `PromptLanesJob().version`, and the summary shape.
- Produces in FeedbackKit, inside `PromptLanes`:
  - `public struct Entry: Equatable, Sendable { public var item: String; public var severity: Severity?; public var size: Size? }` (both nil means not rated)
  - `public var laneA: [Entry]`, `public var laneB: [Entry]`, `public var askFirst: [String]`, and a memberwise `public init(laneA:laneB:askFirst:)`
  - `public var promptLines: [String]`
  - `PromptBuilder.render(_:folderPath:redo:refined:lanes: PromptLanes? = nil)`: with a value, append `""` and `lanes.promptLines` after the Context line and before `</feedback_bundle>`.
- Produces in JevKit (`PromptLanesPlan`, a `public enum`):
  - `public static func plan(round: FeedbackRound, file: JevRecordFile) -> PromptLanes?`
  - `public static func forPrompt(round: FeedbackRound, file: JevRecordFile?, flags: (FeatureFlag) -> FlagState) -> PromptLanes?`: nil unless `flags(.jevBase) == .on` and `flags(.promptLanes) == .on`, nil when `file` is nil, else `plan`.
  - `public static func loadRecords(folderURL: URL) -> JevRecordFile?`: decodes `jev.json` with ISO 8601 dates; nil when missing, unreadable, or another `schemaVersion`.
- Produces in the app: `FeedbackJev.lanes(for round: FeedbackRound, folderURL: URL) -> PromptLanes?`.

- [ ] **Step 1: Write failing section tests** in `PromptLanesTests.swift`. The full example, exact:

```text
Order and lanes:
These labels come from an automated model. The reviewer's words win. Each item appears once.
Lane A, exact edits. After your plan table, hand these items to a subagent on a fast, low-cost model as one batch, with each item's instruction from manifest.md. In Claude Code, set the subagent's model to haiku. With fewer than three items, do them yourself. Check each edit before you start lane B.
- 3.2 polish, one line
Lane B, needs judgment. Plan these yourself, in this order:
- 4.1 bug, several files
- 7.1 not rated
Ask first: 4.5, 6.2 (no instruction).
Start with lane A. Then work lane B from the top.
```

  - Empty lane A: the line `Lane A, exact edits: none.` and the last line `Work lane B from the top.`
  - Empty lane B: the line `Lane B, needs judgment: none.` and the last line `Start with lane A.`
  - No Ask first line when `askFirst` is empty.
  - `render(round, folderPath:)` and `render(round, folderPath:, lanes: nil)` are equal, and both equal the output of the existing `PromptBuilderTests` fixture. With lanes, the output equals the plain output with `"\n" + promptLines.joined("\n")` inserted before the closing tag line.
- [ ] **Step 2: Write failing plan tests** in `PromptLanesPlanTests.swift`, building `JevRecordFile` values directly (records with `job: "promptLanes"`, `jobVersion: PromptLanesJob().version`, `status: .done`, and a summary in the Task 1 shape):
  - "Every item appears exactly once": the union of lane A, lane B, and Ask first ids equals every item id of the round, with no duplicate.
  - "Order is severity, then capture, then badge": items 2.1 polish, 1.2 bug, 1.1 polish, 3.1 blocker in lane B give `["3.1", "1.2", "1.1", "2.1"]`.
  - "Not rated items come last in lane B, in capture order".
  - "A failed record, a missing record, and another job version make not rated items"; empty notes in those captures still go to Ask first.
  - "Shadow and on records both count".
  - "No rated item gives nil" (all empty notes; and all records failed).
  - "forPrompt is nil when promptLanes is off or shadow, or jevBase is off".
  - "loadRecords reads a jev.json written by the runner" (use `Bundle.make` and a shadow run with a stub transport that returns valid answers for the three questions).
- [ ] **Step 3: Run both packages' tests.** Expected: new tests fail.
- [ ] **Step 4: Implement** `PromptLanes` (Entry, lanes, `promptLines`), the `render` parameter, and `PromptLanesPlan`. The plan walks captures by index and items by `PromptLanesJob.items(in:)`. An empty note goes to Ask first. Else it reads the item's summary field from the capture's `promptLanes` record (status `.done` and the current version); lane `A` or `B` with valid levels gives a rated entry; anything else gives a not rated entry in lane B. Sort each lane by severity descending, then capture, then badge; not rated entries after all rated entries. Return nil when no entry is rated.
- [ ] **Step 5: Wire the app.** `FeedbackJev.lanes(for:folderURL:)` calls `PromptLanesPlan.forPrompt(round:file:flags:)` with `PromptLanesPlan.loadRecords(folderURL:)` and `{ Flags.state($0) }`. Both `PromptBuilder.render` calls in `FeedbackController` pass `lanes: jev.lanes(for: round, folderURL: folder)`. In `copyPromptAndEndRound`, the call stays after `await jev.settle(...)`.
- [ ] **Step 6: Run both packages' tests and the unsigned Debug build** from `AGENTS.md` (`xcodegen generate`, then `xcodebuild ... build`). Expected: all tests pass, `** BUILD SUCCEEDED **`.
- [ ] **Step 7: Commit** by explicit path the six files, message `feat: order and lanes section in the copied round prompt (#72)`.

---

### Task 3: Docs

- [ ] `AGENTS.md`, Jev section: one bullet for `promptLanes` (what it asks, what shadow and on write, the spec path).
- [ ] `docs/agents/bundle-guide.md`: one line on the Order and lanes section of a copied round prompt.
- [ ] Commit with `git add -f` for the two files, message `docs: lanes and priority in the agent guides (#69)`.
