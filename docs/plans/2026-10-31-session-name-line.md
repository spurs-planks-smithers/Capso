# Plan: first line "Session Name: <round title>" (#198)

Date: 2026-10-31. Branch: `claude/magical-jones-ab0ded`. Issue: #198. Related: #164, #165.

## Hold rule

Drew decided that this change must not ship in 0.6.0. `origin/main` `VERSION` read 0.5.0 on 2026-10-31. So the pull request stays a draft. It merges only after `VERSION` on `origin/main` is 0.6.0 or higher. Then: rebase, rebuild, rerun the existing tests, mark ready, squash-merge on green CI.

## Behavior (Drew, 2026-10-31)

- Line 1 of a pasted prompt reads `Session Name: <name>`. The tag line (`<feedback_bundle ...>`) follows it.
- Four places: round prompt, capture prompt, selection prompt, zip `README.md`.
- `<name>` is the Recent Rounds title (`RoundTitle`): the reviewer's own words, 50 characters at most.
- With no reviewer words, `<name>` is a date and time label, so two rounds never share a name.
- The name is one line and holds no `<`, `>`, backtick, or newline. It uses reviewer words only, never window titles or OCR text.
- No network call, and no delay of a copy.

## Calls I make

1. **Round:** `RoundTitle.title(for: round)`.
2. **Capture:** the same cleaning on that capture alone: its first instruction, else its note. A new `RoundTitle.title(for: capture)` shares the code with the round version.
3. **Selection:** the title of the first selected entry's capture. The first entry is the oldest capture, the same order as the prompt body. One checked capture then gets the same name as its capture prompt.
4. **Zip README:** a round zip uses the round title. A selection zip uses the first capture, as the selection prompt does.
5. **Date fallback is absolute:** "Oct 31, 6:27 AM", the form Recent Rounds shows for rounds older than yesterday. Recent Rounds itself shows "Today" or "Yesterday" for newer rounds. A session name outlives the day, and "Today, 6:27 AM" would name two rounds from different days the same. A round uses `startedAt`. A capture or selection uses the capture's `capturedAt`, because those prompts have no round.
6. **Cleaning:** turn `<`, `>`, backtick, and white space into one space. Drop control, format, and other invisible characters (zero-width, tag, and filler characters). Cut to 50 characters again after cleaning. If nothing is left, use the date label.
7. **Flag:** the existing `sessionTitle` flag, on in both channels. No new flag. The zip path gets a `sessionTitle` parameter, because zip code had no flag before.
8. **Old `sessionNameLine`:** reword it to point at the first line. Text: "The first line is this session's name. If your tool lets you rename this session, set its name to that text now." #164 found that an agent which can rename its session does so when asked. The reworded line keeps that and makes the agent use Nextshot's name, not a second one. The paste test below decides nothing about this line, because no tool I can drive renames a session.

## Files

- New: `Packages/FeedbackKit/Sources/FeedbackKit/SessionName.swift`.
- Edit: `RoundTitle.swift` (capture variant, shared code), `FeedbackLibrary.swift` (public absolute date label), `PromptBuilder.swift` (line 1 in three prompts, reworded line), `ZipText.swift` and `ZipWriter.swift` (README line 1, `sessionTitle` parameter), `App/Feedback/FeedbackZip.swift` (pass the flag).
- Tests that the change breaks (update only these): `SessionTitlePromptTests` (line indexes, reworded line). Check `AgentNeutralTextTests`, `ZipTextTests`, and every `hasPrefix` test.
- Docs: `AGENTS.md`, `docs/agents/bundle-guide.md`, `docs/FORK_NOTES.md` (only if an upstream file changes; none expected), Guides `reuse-rounds.mdx` and `first-handoff.mdx`, one line under Unreleased in `CHANGELOG.md`. Files on disk (`prompt.md`, `<stem>-prompt.md`) never change.
- Do not bump `VERSION`. Do not release.

## Verify

- `swift test --package-path Packages/FeedbackKit`, and JevKit tests in Release (`PromptBuilder` is shared).
- App build with `xcodebuild` (see `AGENTS.md`), and the app tests.
- A throwaway script renders all four texts for a titled round and an untitled round. Check line 1 of each.
- Paste test in each agent tool I can drive. Report a tool I cannot drive as not tested.
- No live install. Drew's Nextshot Dev keeps running. The live steps stay unverified in the pull request.
