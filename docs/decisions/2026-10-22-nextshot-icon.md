# Nextshot gets its own icon

Date: 2026-10-22. Decided by Drew.

## Decision

Nextshot uses its own app icon and menu bar mark: a teal rounded square with a mint chevron, separated by a cut gap, on a graphite body. It ships as an Icon Composer `.icon` file. The spec is `docs/brand/nextshot-mark.md`.

## Why

- **License.** Capso's Business Source License says it grants no right in the Licensor's trademark or logo (`LICENSE`, line 64). Until this change, the Nextshot build shipped Capso's icon.
- **Meaning.** The square is the capture. The chevron is the next step, the hand-off to an agent.
- **Apple's guidance.** The Human Interface Guidelines (App icons, changed 2026-06-08) ask for simple icons with a minimal number of shapes and favor filled, overlapping shapes. They say to let the system add blur, highlights, and shadows.
- **Format.** An `.icon` file lets macOS draw all six appearances: default, dark, clear light, clear dark, tinted light, and tinted dark.

## Options looked at

| Round | Options | Result |
|---|---|---|
| 1 | Flat line drawings | Rejected: not Mac-like |
| 2 | Circle it, drag select, N mark, next shot | Next shot picked as the idea |
| 3 to 4 | Four, then six frame-and-chevron forms in six colors | Frame and chevron in teal picked |
| 5 | Forms in each appearance | Half-clear square fades in clear and black and white |
| 6 to 7 | Centered square, polish, 12 variants | Knockout gap picked |
| 8 to 9 | Real cut, gap widths, shape fixes | Chevron moved right 56, gap 48, rounding 10 |

## Scope

Only the Nextshot build uses the new icon. `scripts/local-project.yml` adds it, so upstream's `project.yml` and `Capso.app` keep Capso's icon. The menu bar mark is fork code in `App/Feedback/`, so both builds show it.

The live check after the first install found Capso's logo on the main capture menu in the menu bar. Drew chose the Nextshot mark for both menu bar items (2026-10-22). A one-line hook edit in `MenuBarController.swift` does it, logged in `docs/FORK_NOTES.md`.
