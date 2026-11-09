# Defer the Windows port and the Chrome pilot, November 9, 2026

### Decision

Windows and Chrome leave the current scope. Both keep their issues, their code, and their plans. Neither is closed, and neither is cancelled. Both carry the new `deferred` label, and neither carries `sev-blocker` any more.

The reason is budget, not doubt. At HEAD `ea93084` the tracker held 30 open issues and 24 of them were `sev-blocker`. Nineteen of those were Windows issues against a 4,417-line C# scaffold in `Windows/` that has no shipping download, no owner, and no user. Four more were the Chrome chain N1 to N4. That left one genuine macOS blocker (#127). A label that covers 24 issues, 23 of which nobody is working on, cannot tell Drew what to do next.

### What was done

A `deferred` label was created: "Planned but deliberately outside the current scope; not scheduled".

Windows issues moved from `sev-blocker` to `sev-bug` and gained `deferred`:

#208, #209, #210, #220, #221, #223, #224, #226, #227, #228, #231, #232, #233, #234, #239, #240, #241, #244, #246.

Chrome issues moved from `sev-blocker` to `sev-bug` and gained `deferred`:

#178, #179, #180, #181.

Windows and Chrome issues that already carried a lower severity gained `deferred` and kept their severity:

Windows #222, #229, #230, #235, #236, #237, #238, #242, #243, #245, #247.
Chrome #124, #172, #177, #182, #185, #186, #188, #189, #190, #191, #192.

43 issues carry `deferred`. Draft PR #173 (the Chrome pilot) stays open and unmerged with a comment recording the park. Closing it would lose the review history.

### The severity tradeoff

`AGENTS.md` requires every open `bug` and `enhancement` issue to carry exactly one severity label. Removing `sev-blocker` from 23 issues would have left each of them with no severity at all, which breaks that rule. There were two honest ways out.

The rejected one: drop the requirement for deferred issues. That rewrites the rule to fit the data and leaves a reader unable to rank a deferred issue against a live one.

The chosen one: give each a severity that describes the problem a user actually meets today. Every one of these is an `enhancement`, and an enhancement that has never shipped is not failing or showing wrong data for anybody, so `sev-blocker` ("the feature fails, shows wrong data, or stops the user from finishing a task") is false on its face. `sev-bug` says the feature is incomplete but the screen still works, which is true: a person on a Mac has no Windows app to be blocked by and no Chrome pilot to be broken by. The severity labels stay honest, the rule stays intact, and `deferred` carries the real signal.

The cost is that `sev-bug` now covers work nobody is doing. That is why `deferred` exists and why the two should be read together. When either effort restarts, the first act is to re-rate from the issues' own text, not from this record.

### The label inventory

`AGENTS.md` said the fork keeps "GitHub's default labels plus the four `sev-` labels". That is now false, so the line was changed to name `deferred` as well, and a bullet below it defines when an issue carries it.

Correction, 2026-11-09: `AGENTS.md` is a fork-only file. `git ls-tree upstream/main` does not list it, and `docs/FORK_NOTES.md` already records it under "Fork-only files". So the edit needs no row in the upstream-edits table, and this record's earlier claim that `AGENTS.md` is tracked upstream was wrong. `docs/FORK_NOTES.md` needs no change for this work.

`AGENTS.md` is git-ignored (`.gitignore` line 27), so it needs `git add -f` to commit.

### The user-facing side

Nextshot has no Windows download. The site shows a disabled "Coming soon" button. That button now tells the truth, because nothing in the current scope will enable it. The FAQ entry in the guides says Nextshot is Mac only and that Windows is planned but not scheduled, so a person on Windows does not wait for a build that is not coming this cycle.

### What would reopen this

A named owner for Windows, or a person who asks for the Windows build and will pay for it. Either one changes the budget question, and the first act is to re-rate the issues and move the label back.

### Notes

- No code was deleted. `Windows/` stays.
- No Windows or Chrome issue was closed.
- The severity ratings are a judgement about today's user-facing state, not a prediction of effort.
