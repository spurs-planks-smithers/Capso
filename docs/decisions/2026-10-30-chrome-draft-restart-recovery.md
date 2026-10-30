# Chrome unsaved drafts survive a browser restart

Date: 2026-10-30. Owner: Drew (product rule), recorded by the #182 restart session. Status: implemented for Nextshot Pilot, pending installed-Chrome restart check. Issue: #186, part of #182.

## Problem

On 2026-10-29 an assessment of runtime 382944f found that an unsaved Pilot capture is lost at browser start. Two paths delete it:

1. `cleanDrafts` runs on `chrome.runtime.onStartup`. It keeps only drafts tied to a live tab. The tab map is in `chrome.storage.session`, which Chrome clears at restart. Tab IDs also change when Chrome restores a session.
2. `chrome.tabs.onRemoved` deletes the draft whenever its review tab closes. Chrome can fire this event during window close, so a quit may delete the draft before `onStartup` runs.

The editor kept the selected dot and unsent edits in `sessionStorage`, which does not survive a restart either. Saved rounds were never affected.

## Decision

An unsaved draft is the user's work. Keeping it costs a few megabytes. It survives a tab close and a browser restart.

| Rule | Value |
| --- | --- |
| Key | The capture ID (a random UUID), never a tab ID |
| Leaves by | Discard capture, Save, or a limit below |
| Age limit | 7 days since the last edit |
| Count limit | 5 drafts, newest kept |
| Size limit | 64 MB of evidence in total, oldest dropped first |
| Newest draft | Always kept, even when it alone passes the size limit |
| When limits run | Browser start, a permission removal, and after each new capture |

Both Chrome and the user reach a draft the same way: Chrome's own session restore reopens `review.html?draft=<id>`, and the popup shows one extra line, "Resume unsaved capture", when a draft exists. The line focuses the open tab for that draft, or opens a new one. It adds no step to the normal capture flow.

Selected-dot and unsent-edit state moved from `sessionStorage` to `localStorage`, keyed by capture ID. The editor removes it on Save and Discard, and removes state for any ID with no draft each time it loads.

## Alternatives rejected

- Keep the old behavior and tell the user. This loses work for no saving of effort. It also contradicts the product rule to minimize inputs and never lose work that is cheap to keep.
- Keep drafts forever. An abandoned capture would hold a page screenshot (possibly private) indefinitely. Seven days matches the length of a pilot test week.
- Ask the user at restart. This adds an input to resolve a routine choice.

## Scope and limits

- Changed: `pilot-background.ts`, `pilot-popup.ts`, `review.ts`, `core/` (`drafts.ts`, `store.ts`). No new permission, timer, alarm, service, or dependency.
- Not changed: the full Nextshot Dev profile (`background.ts`). It keeps the older tab-bound cleanup. Move it to this rule when Dev drafts need the same guarantee. Rolling drafts are separate and stay as they are.
- A draft in an idle open tab can pass the 7 day limit and be deleted by the next prune. This is rare and accepted.
- Evidence tiers: the retention policy and the localStorage rules have local checks (`npm --prefix browser-extension run checks`). The store functions ran against real Chrome IndexedDB in a fixture page on 2026-10-30. A real browser restart with the installed Pilot is not yet observed. #186 stays open until that check exists.
