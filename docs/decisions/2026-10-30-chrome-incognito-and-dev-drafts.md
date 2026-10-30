# Chrome Pilot stays out of Incognito, and Dev keeps drafts like the Pilot

Date: 2026-10-30. Issues: #187 and #188, both children of the #186 draft rule (`docs/decisions/2026-10-30-chrome-draft-restart-recovery.md`), under #182 and #177. Status: implemented in source. Installed check not observed.

## Incognito stance for the Pilot (#187)

The Pilot keeps an unsaved draft for up to 7 days. An Incognito capture would then stay in the normal profile, which defeats the user's reason to use Incognito. No document in the repo allows Incognito for the Pilot. A search of `browser-extension/`, `docs/decisions/`, and the Pilot guides finds no `incognito` setting or statement.

Decision: the Pilot declares `"incognito": "not_allowed"` in `pilot-manifest.json`. Chrome then offers no Allow in Incognito switch for it. The packager (`package-dev.py --pilot`) refuses a Pilot manifest without this value, and `package-audit.json` records the full manifest. The setting adds no permission and no install warning. The Dev profile keeps Chrome's default (`spanning`, Incognito off until the user enables it). Dev is a trial build for the developer, who knows the retention rule.

## Dev profile drafts (#188)

Decision: the Dev profile follows the same retention rule as the Pilot for screenshot drafts. Rolling Round and recording drafts differ and stay bound to their review tab.

| Draft | Rule in Dev | Why |
| --- | --- | --- |
| Screenshot (`kind` capture, no clip) | Keyed by capture ID. Leaves by Discard, Save, or the age, count, and size limits. Pruned at browser start, on a permission removal, and after each new capture. Reachable by "Resume unsaved capture" in the Dev popup. | Same user work as in the Pilot. One rule in both profiles. |
| Rolling Round and recording (`kind` rolling, or a clip) | Bound to the review tab. Deleted when the tab closes, and at browser start when no tab owns them. | They hold screen video, up to 128 MB. They are optional trials. The 2026-10-30 draft decision left Rolling drafts as they were. Keeping video for 7 days needs its own privacy decision. |

The size, count, and age limits count only screenshot drafts, so a large video draft cannot push out a screenshot. The resume line lists only screenshot drafts.

## Changes

- `core/drafts.ts` (`isTabBoundDraft`), `core/store.ts` (`pruneStaleDrafts` and `listDrafts` skip tab-bound drafts; `pruneDrafts` becomes `pruneTabBoundDrafts` and deletes only tab-bound drafts).
- `background.ts` (Dev): startup and permission removal call `pruneTabBoundDrafts` then `pruneStaleDrafts`; a new capture calls `pruneStaleDrafts`.
- `capture.ts`: no tab association for screenshot drafts, in either profile.
- `resume.ts` (new): one resume line shared by `pilot-popup.ts` and `popup.ts`; `popup.html` gains the hidden `resume` button.
- No new permission, timer, alarm, service, or dependency.

## Evidence tier

Fixture: `checks/manifest.test.mjs` and `checks/drafts.test.mjs` cover the manifest value, the permission set, `isTabBoundDraft`, and source guards on the Dev wiring. The store functions against real IndexedDB for Dev were not run in an installed Dev extension.
