# Pilot Default Capture Shortcut

## Finding

Drew reports that Chrome shows no capture shortcut for Nextshot Pilot. Both installed profiles suggest Alt+Shift+B. Chrome cannot assign the same shortcut to both extensions. The manifest suggestion did not establish an installed assignment.

## Correction

Pilot 0.1.1 suggests Option+Shift+P on Mac and Alt+Shift+P on Windows. Dev retains its capture and Rolling defaults. The command name and extension identities stay stable. This supersedes the earlier shared-default ruling in the workflow plan. No new permission, dependency, helper, or polling is added.

Chrome's [Commands API](https://developer.chrome.com/docs/extensions/reference/api/commands) documents unassigned shortcuts and conflicts. Chromium's [command service](https://github.com/chromium/chromium/blob/main/chrome/browser/extensions/commands/command_service.cc) attempts a new default during update when the former suggestion was never assigned. It preserves custom bindings and does not overwrite an occupied key. This is source evidence. Installed acceptance remains separate.

## Verification

- The existing packager rejects the old conflicting manifests before the fix.
- Eight scratch cases verify valid defaults, missing defaults, collisions on each platform, alternate modifier names, and collisions with Dev's other commands.
- TypeScript and both browser profiles build successfully.
- Existing profile, runtime, editor, workflow, matching, shortcut display, icon, and local Jev checks pass. No live model calls run.
- One focused source review finds no material blocker.

## Handoff

Package from committed source. Verify the archive and copy it to the existing visible Pilot folder. Keep the same identity and saved browser data. Ask for one manual Reload, then verify the actual key. Do not ask Drew to assign a key before checking the automatic update.

Keep #177 and #182 open for installed usability and friend acceptance. Keep all Chrome work in Later and outside v0.5.0. Publish no public release.

## October 29 Left-Hand Correction

Drew confirms automatic P assignment after reload. He then confirms that the key opens a captured image without using the popup. He rejects P for reach and explicitly requests Option+Shift+D. Pilot 0.1.2 therefore uses Option+Shift+D on Mac and Alt+Shift+D on Windows. This supersedes the P default above. He wants Nextshot hotkeys reachable with his left hand.

The existing disjoint-default guard still checks D against Dev's B/G defaults. Chromium source supports moving an untouched P binding to D during update. Installed D assignment remains pending a reload and user check. No custom key is overwritten. No new permission, dependency, or runtime behavior is added.
