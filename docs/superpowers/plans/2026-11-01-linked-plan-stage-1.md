# Linked Plan, Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the hand-test kit, a replay harness with today's prompt as the baseline, and the `linkedPlan` copied prompt (design Part A) behind a flag that starts off.

**Architecture:** A small command-line target in FeedbackKit renders copied prompts and round zips from saved rounds, so scripts outside the app can test them. `PromptBuilder` gains a `linkedPlan` parameter that changes only the copied prompts. Python scripts outside the app run Claude Code and Codex in plan-only mode on approved Nextshot rounds and score the output.

**Tech Stack:** Swift 6 (FeedbackKit, Swift Testing), AppKit pasteboard in a Swift script, Python 3 standard library, the `claude` and `codex` command-line tools.

**Spec:** `docs/superpowers/specs/2026-11-01-visual-direction-handoff-design.md` (Parts A and D, and the Part C hand tests). Evidence: `docs/research/2026-11-01-visual-direction-research.md`.

**Scope:** Stage 1 of the design's order (hand tests, replay baseline, Part A). Part C, Part B, and Part E get their own plans after the hand-test results. The live redo measure (design Part D, item 5) needs the Part B signals, so it moves to the Part B plan.

## Global Constraints

- Build on a feature branch cut from `docs/visual-direction-research`, in its own worktree. Other sessions share the main checkout.
- Every new flag starts `off` in both channels with `releasedInBuild: nil`. `scripts/nextshot-flags.sh` `FLAGS=` matches the registry.
- `linkedPlan` changes only copied prompts. `prompt.md`, `<stem>-prompt.md`, `manifest.md`, the zip README, and the Windows golden files stay byte-identical.
- No text that Nextshot writes names an agent product (#109). The prompt names capabilities: "If your tool can start helper agents".
- No screen text (OCR, window titles) enters a copied prompt.
- No network code in FeedbackKit (`NetworkSourceScanTests`).
- The replay sends only rounds on the approved list in `scripts/replay/rounds.txt`. Drew approves the list before the first run.
- Personal repository: add only the tests named in this plan, and update tests that the change breaks.
- Stage files by explicit path. `docs/` and `scripts/` need `git add -f`. Conventional commit prefixes. No AI attribution lines.
- On m5pro, test only with Nextshot Dev, started through `python3 -I scripts/nextshot-local.py open`.

## Review Focus

1. A round with captures but no numbered items (notes only): the ledger lists the notes, the prompt has no Links step, and nothing crashes. Test in Task 5.
2. A dictated instruction with line breaks and 200 words: it stays one ledger line. Test in Task 5.
3. `linkedPlan` and `promptLanes` both on: the lanes section is left out. Test in Task 5.
4. `linkedPlan` on with `sessionTitle` off: the ledger still appears, and no Session Name line appears. Test in Task 5.
5. A selection that spans two rounds: ledger ids use the selection's numbering, never a manifest's. Test in Task 6.

---

### Task 1: Prompt and zip command-line tool

**Files:**
- Modify: `Packages/FeedbackKit/Package.swift` (add the product and target)
- Create: `Packages/FeedbackKit/Sources/NextshotPromptCLI/main.swift`

**Interfaces:**
- Consumes: `FeedbackLibrary.round(named:in:) -> FeedbackRound?`, `PromptBuilder.render(_:folderPath:redo:refined:lanes:sessionTitle:summaries:)`, `ZipWriter.write(kind:entries:into:now:timeZone:...)`, and `FeedbackSelectionEntry(round:capture:folderPath:)`, one entry per capture of the round.
- Produces: the executable `nextshot-prompt` with two commands:
  - `nextshot-prompt round <rounds-root> <folder> [--redo] [--linked]` prints the copied round prompt with `sessionTitle: true` and no summaries.
  - `nextshot-prompt zip <rounds-root> <folder> <out-dir>` writes the round zip and prints its path.
  - `--linked` exits with status 2 and "linkedPlan is not built yet" until Task 8 wires it.

- [ ] **Step 1: Add `.executable(name: "nextshot-prompt", targets: ["NextshotPromptCLI"])` and `.executableTarget(name: "NextshotPromptCLI", dependencies: ["FeedbackKit"])`.**
- [ ] **Step 2: Write `main.swift`.** Plain `CommandLine.arguments` parsing. A missing round prints "round not found: <folder>" to stderr and exits 1.
- [ ] **Step 3: Run it on the nextshot.dev round.**

Run: `swift run --package-path Packages/FeedbackKit nextshot-prompt round "$HOME/Library/Application Support/Nextshot" 2026-10-31-2125-feedback | head -3`
Expected: the first line starts with `Session Name:`, the second with `<feedback_bundle path=`.

- [ ] **Step 4: Run the full FeedbackKit tests.** Run: `swift test --package-path Packages/FeedbackKit`. Expected: all pass, `NetworkSourceScanTests` included.
- [ ] **Step 5: Commit.** `git add Packages/FeedbackKit/Package.swift Packages/FeedbackKit/Sources/NextshotPromptCLI/main.swift` then `git commit -m "feat: add a prompt and zip command-line tool for tests"`.

### Task 2: Paste hand-test kit

**Files:**
- Create: `scripts/paste-test/paste-test.swift`
- Create: `docs/runbooks/2026-11-01-paste-hand-tests.md`

**Interfaces:**
- Consumes: `nextshot-prompt round` and `nextshot-prompt zip` (Task 1).
- Produces: `swift scripts/paste-test/paste-test.swift <mode> [folder]` with modes `t1`, `t4-2000`, `t4-5000`, `t4-10000`, `t4-15000`, and `t6 <folder>`. Each mode clears the pasteboard, writes it, and prints the item types.

- [ ] **Step 1: Write the script.** T1 and T4 use the round `2026-10-31-2125-feedback` (the nextshot.dev page, no private data). T6 takes a round folder with two or more captures from the approved replay list (Task 3, Step 2).
  - `t1`: one `NSPasteboardItem` with the copied capture prompt (`.string`) and the annotated PNG (`.png`).
  - `t4-N`: the same item, with the text padded to N characters by repeating the ledger. The last line is fixed: `LAST LINE: blue heron 47`.
  - `t6`: two items, the copied round prompt (`.string`) and the round zip file URL from `nextshot-prompt zip`.
- [ ] **Step 2: Write the runbook.** Apps: Claude desktop (chat and the Code tab), Claude Code in Terminal, ChatGPT desktop, claude.ai and chatgpt.com in Chrome, Cursor, the Codex app. For each app and test, the runbook says: run the mode, open a new chat, press Command+V, and send the fixed question. It holds one result row per app and test.
  - T1 question: "What does badge 1.1 point at?" Pass: the text appears, one image attaches, and the answer names the download buttons.
  - T4 question: "Quote the last line of my message." Pass: the answer contains `blue heron 47`. Run in a new chat and in a chat with 20 or more earlier turns.
  - T6 question: "What does the image show at badge 2.1?" Pass: the zip attaches, and the answer describes the region under badge 2.1.
- [ ] **Step 3: Check each mode.** Run each mode, then `osascript -e 'clipboard info'`. Expected: `t1` and `t4-N` list text and PNG data. `t6` lists text and a file URL.
- [ ] **Step 4: Commit.** `git add -f scripts/paste-test/paste-test.swift docs/runbooks/2026-11-01-paste-hand-tests.md` then `git commit -m "test: add the paste hand-test kit"`.
- [ ] **Step 5: Drew runs the hand tests** (about 15 minutes) after he approves the replay list in Task 3, Step 2, and fills the result table. Commit the filled runbook with `docs: record paste hand-test results`. The Part C plan starts from these results.

### Task 3: Replay harness, baseline run

**Files:**
- Create: `scripts/replay/rounds.txt`
- Create: `scripts/replay/replay.py`

**Interfaces:**
- Consumes: `nextshot-prompt round` (Task 1).
- Produces: `python3 -I scripts/replay/replay.py --variant today|linked [--runs N] [--agents claude,codex] [--yes]`. Output goes to `build/replay/<YYYY-MM-DD>/<round>/<agent>-<variant>-<run>.json`, one JSON object per run: `round`, `agent`, `variant`, `run`, `commit`, `model`, `output` (the agent's final text), `tokens` (input and output counts).

- [ ] **Step 1: Draft `rounds.txt`.** One folder name per line, `#` for comments. Candidates are rounds with two or more captures whose notes are about Nextshot's own app or site. Leave out test rounds (notes such as "asdf") and any round whose images show mail, Nextiva reports, or customer data. A capture of the Nshot menu shows the app under it, so open every image before listing a round.
- [ ] **Step 2: Drew approves the list.** No run happens before this approval.
- [ ] **Step 3: Write `replay.py`.**
  - Commit for a round: `git rev-list -1 --before=<startedAt> origin/main`, checked out with `git worktree add --detach` under `build/replay/worktrees/`.
  - Prompt: `nextshot-prompt round ...` plus a final line. For `today`: "Replay run: write your plan table, any groups of related items, and your questions. Make no edit." For `linked`: "Replay run: write the Links section, the plan table, and your questions. Make no edit."
  - Claude: `claude -p <prompt> --model claude-opus-5-5 --allowedTools Read,Grep,Glob --output-format json` with the worktree as the working folder.
  - Codex: `codex exec --sandbox read-only --json -C <worktree> <prompt>`.
  - Before any run, print the run count. Stop unless `--yes` is given.
- [ ] **Step 4: Run the baseline.** Run: `python3 -I scripts/replay/replay.py --variant today --runs 1 --yes`. Expected: one JSON file per round and agent, each with a non-empty `output`.
- [ ] **Step 5: Commit.** `git add -f scripts/replay/rounds.txt scripts/replay/replay.py` then `git commit -m "test: add the replay harness for copied prompts"`. `build/` stays out of git, because outputs hold Drew's words.

### Task 4: The `linkedPlan` flag

**Files:**
- Modify: `Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift` (a case after `updateReminder`, and its spec)
- Modify: `scripts/nextshot-flags.sh` (`FLAGS=` line)
- Modify: `Packages/FeedbackKit/Tests/FeedbackKitTests/FeatureFlagsTests.swift` (`registryContents`)

**Interfaces:**
- Produces: `FeatureFlag.linkedPlan`, spec `FlagSpec(issue: <N>, allowedStates: [.off, .on], devDefault: .off, releaseDefault: .off, releasedInBuild: nil)`. Not dev-only, so an override works in a release build.

- [ ] **Step 1: Open the issue.** Follow the github-account-routing skill and run `github-route status` first. Title: "Linked plan prompt: link related items, keep a ledger, ask once". Labels: `enhancement` and `sev-bug`, in the same call. Use its number as `<N>`.
- [ ] **Step 2: Update `registryContents`.** Append `"linkedPlan"` to the name list and `<N>` to the issue list. Run `swift test --package-path Packages/FeedbackKit --filter FeatureFlagsTests`. Expected: FAIL (no such case).
- [ ] **Step 3: Add the case, its doc comment, and its spec.** Doc comment: "The linked plan prompt (#N). Copied prompts ask the agent to link related items, keep an item ledger, and ask once. Files on disk never change. Code only." Append `linkedPlan:off,on` to `FLAGS=`.
- [ ] **Step 4: Run the flag tests.** Same command. Expected: PASS, the `nextshot-flags.sh` test included.
- [ ] **Step 5: Commit.** `git add` the three files, then `git commit -m "feat: add the linkedPlan flag (#N)"`.

### Task 5: Linked round prompt

**Files:**
- Modify: `Packages/FeedbackKit/Sources/FeedbackKit/PromptBuilder.swift`
- Create: `Packages/FeedbackKit/Tests/FeedbackKitTests/LinkedPlanPromptTests.swift`
- Modify: `Packages/FeedbackKit/Tests/FeedbackKitTests/AgentNeutralTextTests.swift` (add the linked renders to the texts list)

**Interfaces:**
- Consumes: `FeatureFlag.linkedPlan` (Task 4), only by name in docs. `PromptBuilder` takes a plain `Bool`.
- Produces: a `linkedPlan: Bool = false` parameter, last in the list, on both `render` overloads. `linkedPlan: false` output is unchanged. When `linkedPlan` is true, `lanes` is ignored.
- Produces: `static func linkedLedger(_ entries: [(id: String, capture: FeedbackCapture, item: FeedbackItem?)]) -> [String]` (private is fine) and the constants below, reused by Task 6.

Exact copy (the spec fixes it):

```text
Goal: Apply this review feedback to the work it shows. In a repository, change the code or files that produce it.
Items (badge N in capture K is item K.N):
- K.N: <reviewer's words on one line>        (or "(no instruction)")
- Note on capture K: <the capture's general note on one line>
Work method:
1. Links: Before your plan, write a Links section. Group the items that share one intent or one cause, across captures. Give each group its item ids and the one decision that applies to all of them. Look for one shared source in the code, such as a component, a style, or a string. An item can stand alone.
2. Plan: Write a table with the columns item, group, place, and change. Then continue without waiting.
3. Scope: A group's decision reaches unmarked places only when the reviewer's words ask for it, such as "everywhere", "all", or "never". List other places it would affect under Suggestions, and do not change them.
4. Questions: Do every clear item first. Make no edit on an item with no instruction, on items that conflict, or where two readings would lead to different work. Ask once at the end, with all of their ids in one message.
5. Helpers: If your tool can start helper agents, give a helper only a group whose files no other group touches. Keep the Links, the shared decisions, and the plan yourself. Give the helper the item ids, the reviewer's exact words, the image path, the box, and the shared decision. Do not use helpers to check work.
Authority line 2: - If the text and the image conflict, or an item has no instruction, make no edit to it. Ask about it in your one question at the end.
Report:
- End with the ledger again: one line per item with done, partly, not done, or needs input.
- Give evidence: the file and line, or the changed text. Where your tool can render the result, compare a crop of the same region before and after, and check the property the item names.
```

Order when `linkedPlan` is true: Session Name line (with `sessionTitle`), opening tag, Goal, redo line (with `redo`), ledger, session name line (with `sessionTitle`), blank, How to read (today's steps, refined step included), blank, Work method, Authority (today's lines 1 and 3, the new line 2, the refined line, the no-instruction list), Report, Context. No Verify section. With fewer than three items, Work method drops Links and Helpers and numbers the rest 1 to 3, and the Plan columns are item, place, and change.

- [ ] **Step 1: Write the failing tests** in `LinkedPlanPromptTests` (`@Suite("Linked plan prompt")`). Fixture: `FeedbackFixtures.round(captures: [pricingCapture(index: 1), pricingCapture(index: 2)])` (six items, 1.3 and 2.3 with no instruction). Path `/Users/test/Feedback/2026-10-20-1912-pricing-page`.
  - `ledgerListsEveryItemBeforeHowToRead`: each of `1.1`, `1.2`, `1.3`, `2.1`, `2.2`, `2.3` appears as `- K.N:` before `How to read the bundle:`; `#expect(prompt.contains("- 2.3: (no instruction)"))`.
  - `linkedSectionsInOrder`: positions of `Goal:`, `Items (badge N`, `How to read the bundle:`, `Work method:`, `Authority:`, `Report:`, `Context:` are increasing; `#expect(!prompt.contains("Verify:"))`; `#expect(prompt.contains("1. Links:"))`.
  - `noInstructionStillListed`: `#expect(prompt.contains("Items with no instruction: 1.3, 2.3."))`.
  - `longDictationIsOneLine`: an instruction of 200 words with two line breaks renders as one `- 1.1:` line.
  - `notesOnlyRoundHasNoLinks` (Review Focus 1): a capture with a note and no badges gives `- Note on capture 1:` and no `Links:`.
  - `lanesLeftOut` (Review Focus 3): with a non-empty `PromptLanes`, the output has no `Order and lanes`, `Order`, or `Lanes` heading.
  - `ledgerWithoutSessionTitle` (Review Focus 4): `sessionTitle: false` gives the ledger and no `Session Name:`.
- [ ] **Step 2: Run them.** Run: `swift test --package-path Packages/FeedbackKit --filter LinkedPlanPromptTests`. Expected: FAIL (no `linkedPlan` parameter).
- [ ] **Step 3: Implement the parameter and the linked rendering in `PromptBuilder.swift`.** Keep today's code path untouched for `linkedPlan: false`. Reuse `oneLine`.
- [ ] **Step 4: Add the linked renders** to the texts list in `AgentNeutralTextTests` ("round prompt (linked)", "round prompt (linked, session title)") and raise its `texts.count` floor by two.
- [ ] **Step 5: Run the full FeedbackKit tests.** Run: `swift test --package-path Packages/FeedbackKit`. Expected: all pass, `GoldenBundleTests` unchanged.
- [ ] **Step 6: Commit.** `git commit -m "feat: render the linked round prompt behind linkedPlan (#N)"` with the three files.

### Task 6: Linked capture and selection prompts

**Files:**
- Modify: `Packages/FeedbackKit/Sources/FeedbackKit/PromptBuilder.swift`
- Modify: `Packages/FeedbackKit/Tests/FeedbackKitTests/LinkedPlanPromptTests.swift`
- Modify: `Packages/FeedbackKit/Tests/FeedbackKitTests/AgentNeutralTextTests.swift`

**Interfaces:**
- Consumes: the ledger helper and constants from Task 5.
- Produces: `linkedPlan: Bool = false`, last, on both `renderCapture` overloads and on `renderSelection`. The capture prompt keeps its "Open these files first" list before the ledger. The selection prompt keeps its per-capture file lines, followed by one ledger in selection numbering.

- [ ] **Step 1: Write the failing tests.**
  - `captureWithThreeItemsHasLinks`: `renderCapture(pricingCapture(), ..., linkedPlan: true)` contains `1. Links:` and `- 2.3: (no instruction)`.
  - `captureWithTwoItemsHasNoLinks`: a capture with two badges has no `Links:` and no `Helpers:`, and has `1. Plan:`.
  - `selectionUsesSelectionIds` (Review Focus 5): two entries from different rounds, both with capture index 2, give ledger ids `1.1` to `1.3` and `2.1` to `2.3`.
- [ ] **Step 2: Run them.** Same filter. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Add** "capture prompt (linked)" and "selection prompt (linked)" to `AgentNeutralTextTests`. Run the full FeedbackKit tests. Expected: all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat: linked capture and selection prompts (#N)"` with the three files.

### Task 7: Wire the flag into the app

**Files:**
- Modify: `App/Feedback/FeedbackController.swift` (the five `PromptBuilder` calls at lines 494, 804, 807, 821, and 1448 on `origin/main` at `2374e1a`)

**Interfaces:**
- Consumes: `linkedPlan:` from Tasks 5 and 6, and `Flags.isOn(.linkedPlan)`.

- [ ] **Step 1: Pass `linkedPlan: Flags.isOn(.linkedPlan)` at all five calls.** Leave `ZipText`, `ZipWriter`, and `FeedbackRoundStore` calls as they are.
- [ ] **Step 2: Build the Dev app.** Run `python3 -I scripts/nextshot-local.py check`, then `scripts/build-local.sh Debug`. Expected: the build succeeds and installs `~/Applications/Nextshot Dev.app`. If a Nextshot that you did not start is running, ask Drew before you build.
- [ ] **Step 3: Check the copy.** Run `scripts/nextshot-flags.sh set linkedPlan on`, then open the app with `python3 -I scripts/nextshot-local.py open`. Drew presses Option+Shift+C in an active round. Run `pbpaste | head -30`. Expected: the ledger appears after the Goal line.
- [ ] **Step 4: Reset the flag.** Run `scripts/nextshot-flags.sh reset linkedPlan`.
- [ ] **Step 5: Commit.** `git commit -m "feat: copy linked prompts when linkedPlan is on (#N)" -- App/Feedback/FeedbackController.swift`.

### Task 8: Linked replay, scoring, and report

**Files:**
- Modify: `Packages/FeedbackKit/Sources/NextshotPromptCLI/main.swift` (`--linked` passes `linkedPlan: true`)
- Create: `scripts/replay/score.py`
- Create: `docs/evals/2026-11-01-linked-plan-replay.md`

**Interfaces:**
- Consumes: the run files from Task 3, `feedback.json` of each round.
- Produces: `python3 -I scripts/replay/score.py build/replay/<date>` prints one table row per agent and variant, and writes `score.json` beside the runs.

Measures (design Part D, bar in design Part D item 4):

| Measure | How `score.py` computes it |
|---|---|
| Ledger coverage | Share of the round's item ids found as `\bK\.N\b` in the output. Bar: 100% in every run. |
| Cross-capture groups | Lines in the Links section (or the groups part, for `today`) that hold ids from two or more captures. |
| Question precision | Ids named in the last paragraph that holds a question mark, against ids with no instruction. Bar: only such ids in at least 90% of runs. |
| Tokens | From the run file. Bar: `linked` at most 1.3 times `today`, per agent. |
| Group fit | The other vendor's agent rates each group 1 to 5: "Does this one decision fit every item in the group?" Bar: `linked` mean at least the `today` mean. |

- [ ] **Step 1: Wire `--linked`.** Run `nextshot-prompt round ... --linked | grep -c "1. Links:"`. Expected: `1`.
- [ ] **Step 2: Run the linked replay.** Run: `python3 -I scripts/replay/replay.py --variant linked --runs 1 --yes`. Expected: one file per round and agent.
- [ ] **Step 3: Write `score.py` and run it** on the date folder. Expected: a table with both variants for both agents.
- [ ] **Step 4: Write the report.** Numbers only, with no reviewer words: rounds, runs, models, the five measures for each variant and agent, and pass or fail against each bar. End with the decision Drew must make: keep `linkedPlan` off, or try it in his Dev build.
- [ ] **Step 5: Commit.** `git add Packages/FeedbackKit/Sources/NextshotPromptCLI/main.swift` and `git add -f scripts/replay/score.py docs/evals/2026-11-01-linked-plan-replay.md`, then `git commit -m "test: score the linked plan replay"`.

### Task 9: Docs

**Files:**
- Modify: `AGENTS.md` (Feature flags section)
- Modify: `docs/agents/bundle-guide.md` (Rules)

- [ ] **Step 1: Add one `AGENTS.md` bullet** after the `zipHandoff` bullet: `linkedPlan` (#N) is not a Jev flag and not dev-only. It starts off in both channels. With it on, copied prompts open with an item ledger and ask for Links, a plan table, one batch question, and the ledger again in the report. Files on disk never change. The design is `docs/superpowers/specs/2026-11-01-visual-direction-handoff-design.md`.
- [ ] **Step 2: Add two bundle-guide rules.** "**Links come first when asked.** A prompt can ask for a Links section: group related items, one shared decision per group, before the plan." And: "**Ask once.** Finish the clear items, then ask about the rest in one message."
- [ ] **Step 3: Commit.** `git add -f AGENTS.md docs/agents/bundle-guide.md` then `git commit -m "docs: describe the linkedPlan flag (#N)"`.
