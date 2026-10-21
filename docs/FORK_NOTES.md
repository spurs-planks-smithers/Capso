# Fork notes

Fork: `spurs-planks-smithers/Capso`. Upstream: [lzhgus/Capso](https://github.com/lzhgus/Capso). Fork base: `8f07fb6` (v1.2.5).

This file logs every edit to an upstream file: the file, the reason, the lines, and the upstream PRs at risk of a merge conflict. Read it before each upstream merge.

## Upstream file edits

| File | Reason | Lines | Upstream PRs at risk |
|---|---|---|---|
| n/a | No upstream file is edited yet | n/a | n/a |

## Fork-only files

| Path | Purpose |
|---|---|
| `AGENTS.md`, `CLAUDE.md` | Agent instructions. `CLAUDE.md` imports `AGENTS.md`. |
| `docs/plans/2026-10-20-feedback-sessions-phase1.md` | Phase 1 plan |
| `docs/FORK_NOTES.md` | This log |
| `docs/decisions/2026-10-20-feedback-bundle-format.md` | Why the bundle has its format |

## Open upstream PRs that touch hook files

Checked 2026-10-20.

| PR | Files it shares with the fork's hook points |
|---|---|
| [#349](https://github.com/lzhgus/Capso/pull/349) | `AppDelegate.swift`, `MenuBarController.swift`, `ShortcutSettingsView.swift`, `project.yml` |
| [#348](https://github.com/lzhgus/Capso/pull/348) | `ShortcutSettingsView.swift`, `project.yml` |
| [#291](https://github.com/lzhgus/Capso/pull/291) | `AppDelegate.swift` |

- PR #349 checks shortcut conflicts over `KeyboardShortcuts.Name.allCapso`. The fork's `feedbackCapture` name is not in that list, so that check does not see it.
- No open upstream PR edits `CaptureCoordinator.swift`.
