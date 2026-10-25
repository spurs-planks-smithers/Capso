# Session: one-breath notes (#40), 2026-10-24

Closed 21:15 PDT. A side session that the orchestration session started. Worktree `.claude/worktrees/one-breath-aa3fe0`, branch `claude/one-breath-aa3fe0`. Outcome: Drew paused the feature after the trial. The code merges with the `oneBreath` flag locked off, and #40 moves to the backlog.

## Work log

- Read Drew's 9 rounds (101 answers, later 103). No answer was a one-breath answer. Numbers in answers usually mean something else ("footnote number one", "page 3"). A loose number splitter misfired on 6%. A strict one misfired on 0.
- Research: Wispr Flow removes spoken self-corrections before the text arrives. Split-then-assign works for multi-intent utterances (SPM, ACL 2023). Talon chains voice commands with a spoken separator word.
- Interviewed Drew. His decisions are in the spec decisions log. The main ones: he prefers one step per circle; the trial is on purpose; the review file is automatic in each round folder; build only if one breath feels faster and at least 90% of parts are right.
- Drew's Wispr Flow test: a spoken "One, ... Two, ... Three, ..." arrives as a numbered list, one item per line.
- Wrote the spec `docs/superpowers/specs/2026-10-24-one-breath-design.md`. A Sonnet builder check raised five questions. Four were settled in the spec. One changed Drew's bar from 95% to 90%.
- Built `OneBreathSplitter` (FeedbackKit, a Sonnet executor, reviewed here), `OneBreathJob`, and `OneBreathReview` (JevKit). Asked the Jev base for a review-file hook and a failure path. Both landed in `faf96ee`.
- Trial on combined build 622 with words, crops, and screen text: 3 captures, 11 parts. Code gave every part the circle its number named. Jev agreed at 0.8 or more on 7 parts and was unsure on 4. One request per capture, 575 ms, about 8,400 input tokens.
- Drew's verdict (21:10 PDT): "Overall, I don't think this is a very good feature. I think we should deprioritize this, table it, and make the feature flag hidden for now." He chose to lock the flag off and to merge the code.

## Commits

`05bd74c` spec, `88a03cb` split code, `8621a66` job, `1d741aa` shared runner test line, `7559f85` review hook and failure path, `aed31e6` notice cleanup, then the flag lock and this note.

## Git

- Pushed `claude/one-breath-aa3fe0` after `github-route status` passed.
- PR [#67](https://github.com/spurs-planks-smithers/Capso/pull/67) into `feature/feedback-sessions`. Fork CI is off, so it shows zero checks. Local results: FeedbackKit and JevKit tests pass, and the unsigned Debug build passes.
- Sub-issues #53, #54, #55, and #56 are closed. #40 stays open in the backlog.

## Open

- To restart: add `.shadow` back to the `oneBreath` entry in `FeatureFlags.swift` and to `scripts/nextshot-flags.sh`, then run the trial in the spec again.
- Every flag override is reset to none.
