# Offline update reminder, October 31, 2026

Drew asks for a low-friction way to tell people about new builds (#203). Nextshot has no network access, and builds ship every few days.

### Decision

About 7 days after a build first runs, Nextshot shows one toast and a row in the Nshot menu. The toast reads "New Nextshot builds ship often. Nextshot stays offline, so check the Nshot menu." The row reads "Get the latest version…" and sits under the version line. A click opens `https://nextshot.dev/#from=<version>` in the default browser and hides the row for that build.

The app cannot know whether a newer build exists, so the toast does not claim one is out. It says builds ship often and points to the menu. The website does the comparison.

| Topic | Rule |
| --- | --- |
| Clock | 7 days from the first run of the current build. A new build restarts the clock and clears both marks, so a person who just updated stays quiet. |
| Audience | Only people with at least one saved round. |
| Toast | Once per build, at the first idle moment: no active round, no open capture, no round ending. Checked 60 seconds after launch, at each Mac wake, and every 3 hours. It never shows during a menu open. |
| Row | From day 7 until the person clicks it or a new build runs. |
| Switches | Feature flag `updateReminder` (on in both channels), the Settings toggle "Remind me about new versions" (General > About, on by default), and the `automaticUpdates` capability. If Sparkle ever turns on, the reminder hides itself and the toggle disappears. |
| Clock set back | The wait restarts. The marks stay, so the toast cannot repeat. |

### Privacy

The app makes no request. The version travels in the `#` part of the link. A browser never sends that part to a server, so nextshot.dev learns nothing from the click. A small script on the download page reads the part in the browser and says whether a newer build is out. The script must make no request of its own: its test fails on `fetch`, `XMLHttpRequest`, `sendBeacon`, `Image`, and `WebSocket`.

`NetworkSourceScanTests` allows one URL literal in `UpdateReminder.swift` and bans every other network rule there. A test fails if the literal moves or a second one appears.

### Why this way

| Choice | Reason |
| --- | --- |
| Toast plus menu row | A toast cannot hold a link. A row can. The toast makes the row visible once, and the row stays. |
| Clock from the first run of each build | A "first launch ever" date would fire again right after every update, because settings survive the in-place DMG installer. |
| `#` fragment, not `?` query | A query reaches the server logs. A fragment does not. This keeps "we take none of your data" true. |
| No macOS notification | It asks the system for permission, which is the friction Drew wants to avoid. |
| No repeat toast | A person who ignores one toast gets the row only. Drew prefers no nagging. |

### Relation to Sparkle (roadmap M3)

The reminder bridges the gap until M3. It does not cancel M3. The `automaticUpdates` capability turns the reminder off, so the two never run together. M3 stays an open decision.

### Release steps

1. Deploy the website note first (a separate pull request). An app that links to a page without the note still works, but the note does the comparison.
2. Check `releasedInBuild` for `updateReminder` in `FeatureFlags.swift`. It is a best guess (895) and nothing reads it at run time. Set it to the release's build number when the release is cut.
3. Refresh the Guides in the release change: `install.mdx` (Install an update) and `settings/general.mdx` (the new About row). Set `minVersion` to the release that ships the reminder, so the page shows a notice to people on an older download.

### Guides review

The published Guides describe released Nextshot 0.5.0. This change edits no Guides page, because the reminder is not released yet and the Guides teach released behavior. Step 3 above refreshes them. This change deploys no website or app release.
