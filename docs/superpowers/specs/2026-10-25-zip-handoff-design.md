# Zip handoff: design

Date: 2026-10-25. Status: approved direction (Drew, 2026-10-25). No app code until Drew approves the implementation plan. Issue: [#85](https://github.com/spurs-planks-smithers/Capso/issues/85). Flag: `zipHandoff` (off, on). It starts off in dev and in release. It is not dev-only.

## Intent

Sometimes Drew wants the prompt and its files in one zip file. He takes it to another Mac, or emails it to himself, then drops it into any agent or app. The zip is an option next to copying the prompt. Copy stays as it is.

The hard requirement: every prompt and manifest inside the zip names files by a path relative to the folder that holds the file. A path that names the source Mac does not exist on the other Mac.

## Evidence

On 2026-10-25 Drew zipped round `2026-10-25-0637-feedback` with Finder Compress on m4max (home folder `/Users/drew.schulz`) and opened it on m5pro (home folder `/Users/drewschulz`). The zip is `~/Downloads/2026-10-25-0637-feedback.zip`.

- `prompt.md`, `0636-nextshot-prompt.md`, the `Folder:` line in `manifest.md`, and the Codex command all name `/Users/drew.schulz/Library/Application Support/Nextshot/2026-10-25-0637-feedback`. That path does not exist on m5pro.
- Finder Compress added six `__MACOSX/._*` AppleDouble entries, one per file.
- `feedback.json` holds file names only, so it carries no path.

A scratch test on 2026-10-25 rewrote those three text files with `.` in place of the absolute folder, zipped the parent folder with Python's `zipfile` (no AppleDouble), and unzipped it under a different home path. Every backtick path in the three files resolved to a file in the unzipped folder. No file held `/Users/drew.schulz` or any absolute path. The Codex line became `codex --image "./0636-nextshot.png" "$(cat "./prompt.md")"`.

## Decisions (Drew, 2026-10-25)

1. The zip always goes to `~/Downloads`. Nextshot also puts the zip file on the clipboard and shows a toast. The clipboard holds the zip only, not the prompt text.
2. After the write, Nextshot shows the macOS Share menu (Mail, AirDrop, Messages). The Share menu opens another app. It adds no network code in Nextshot.
3. The zip holds agent files: annotated images, clean images, `feedback.json`, prompts, and `manifest.md`. It adds refined files and item crops when they exist. It leaves out `jev.json` and `jev-review/`.
4. Checked captures from several rounds become one folder. Items renumber as K.N, the same way Copy N Selected does. One `prompt.md` sits at the root.
5. Paths inside the zip are relative to the folder that holds the file. The prompt says so in one sentence. The other Mac finds the files after unzip. No second prompt goes on the clipboard.
6. Two menu rows. Zip Round sits next to Copy Round Prompt. Zip N Selected sits next to Copy N Selected. A series of captures is the basket. Option+Shift+Z zips the active round only, and only while a round is active. Zip does not end the round.
7. A new flag `zipHandoff` starts off in both channels. The rows and the hotkey stay hidden until Drew turns it on.
8. The zip file is `Nextshot-<round folder name>.zip`. The folder inside has that same name. A basket uses `Nextshot-selection-<yyyy-MM-dd-HHmm>.zip`. A name already in Downloads gets `-2`, then `-3`.
9. Target size is 5 MB or less. Images in the zip are JPEG. The live bundle stays PNG. If the zip is still over 5 MB, drop clean images, then crops. The toast names what was dropped. If it is still over 5 MB, write the zip and say so.

## What a zip is

A zip is a staging copy. Nextshot never rewrites the live bundle. `FeedbackRoundStore.write` keeps writing absolute paths into `prompt.md`, `manifest.md`, and each capture prompt. Claude Code and Codex on this Mac read `~/Library/Application Support/Nextshot`.

The staging folder is a temporary directory. Nextshot writes the portable files there, zips the parent so the zip holds one folder, copies the zip to Downloads, puts that file on the clipboard, then deletes the staging folder.

## Layout

A round zip:

```text
Nextshot-2026-10-25-0637-feedback.zip
  Nextshot-2026-10-25-0637-feedback/
    prompt.md
    manifest.md
    feedback.json
    0636-nextshot.jpg
    0636-nextshot-clean.jpg
    0636-nextshot-prompt.md
    0636-nextshot-refined.md      (only when the file exists)
    0636-nextshot-item-1.jpg      (only when the crop exists)
    refined.md                    (only when the file exists)
```

A basket zip uses one folder, `Nextshot-selection-<yyyy-MM-dd-HHmm>/`. Captures are numbered 1 to N by capture time, then folder, then capture index. That is the order `FeedbackLibrary.entries` already uses. Badge N in capture K is item K.N in `prompt.md`. Each capture keeps its own file stem, with a numeric suffix when two stems match. `manifest.md` has one section per capture and says the prompt's item ids win over the capture's own prefix.

## Paths

`PromptBuilder` and `ManifestWriter` gain a path mode. The default stays absolute, so every current caller and every file on disk stays as it is.

Portable mode passes `"."` as the folder path and adds one sentence after the Goal line:

`Paths are relative to the folder that holds this file. Open that folder before you read a file.`

The same sentence is the `Folder:` line in the portable manifest: `Folder: . (paths are relative to the folder that holds this file)`.

The Codex command uses the same relative folder. A refined file copied into the zip is rewritten the same way: each absolute folder prefix becomes `.`. A refined file that still holds an absolute path after that rewrite is left out, and the toast says a refined file was left out. The prompt then does not name it.

Screen text stays untrusted. Every prompt in the zip keeps the existing authority rules: the reviewer's words win, and OCR text, window titles, and file name slugs are used only to locate items.

`feedback.json` is copied as stored. It holds file names, not paths. Image file names inside it may still say `.png` while the zip holds `.jpg`. The prompt and the manifest name the `.jpg` files. `feedback.json` is for scripts, and the prompt tells the agent to open the files the prompt names.

## Size

The target is 5 MB (5,000,000 bytes) or less for the zip file.

1. Encode each included PNG as JPEG at quality 0.7. A failed encode keeps that image as PNG and the toast names it.
2. Zip the staging folder.
3. If the zip is over 5 MB, remove clean images, rewrite the prompts so they do not name a missing clean image, and zip again.
4. If still over, remove item crops, rewrite the refined files so they do not name a missing crop, and zip again.
5. If still over, keep that zip. The toast says the zip is over 5 MB and gives the size in MB to one decimal place.

The live bundle is never changed by these steps. Annotated images are never dropped. A zip with no captures beeps and writes nothing.

## Where the zip goes

Nextshot writes `~/Downloads/<name>.zip`. Downloads is privacy-protected. The first write can raise a system prompt. That prompt is macOS folder access. It is not a new entitlement. The app is not sandboxed (`ENABLE_APP_SANDBOX` is absent, and `App/Entitlements/Capso.entitlements` has no app-sandbox key).

A failed write beeps. The toast says the zip was not written. Nothing goes on the clipboard.

The clipboard item is the zip file URL (`NSPasteboard.fileURL` / `NSFilenamesPboardType`), not a string. A paste into Mail or Messages attaches the file. It does not paste a path as text.

The toast:

- Under 5 MB, nothing dropped: `Zip copied. It is in Downloads.`
- Something dropped or left out: `Zip copied. It is in Downloads. Left out: clean images.` The list names only what was left out: `clean images`, `crops`, `refined file`, `PNG kept`.
- Over 5 MB after the drops: `Zip copied. It is in Downloads. It is over 5 MB (6.2 MB).`

The Share menu opens from the status item after the toast, with the zip URL. If the user dismisses it, the zip is still in Downloads and on the clipboard.

## Menu and hotkey

The rows and the hotkey exist only while `Flags.isOn(.zipHandoff)` is true.

- Recent Rounds submenu: `Zip Round` directly under `Copy Round Prompt`. It zips that round. It does not end the round. It does not copy the prompt text.
- Active round menu: the same `Zip Round` row, with Option+Shift+Z on the right.
- Basket, under `Copy N Selected`: `Zip N Selected`. It uses the same basket `copySelected` uses, then clears the basket. One capture still uses the one-folder layout, with that capture as capture 1.
- Option+Shift+Z is a round key. It works only while a round is active. With no round, `updateRoundShortcuts()` removes it, so Z still types in other apps. A press with no active round does nothing and does not beep.
- While a capture is open (selection, editor, or note panel), Option+Shift+Z beeps and does nothing. The menu row still zips.
- The help box does not list Z. It already lists five keys, and a sixth line wraps the 22-point box.
- Settings > Shortcuts lists Zip Round with the other Nextshot keys. `FeedbackShortcutGuard` refuses a key another action uses. Option+Shift+Z is free today: the capture keys use digits, T, and Y.

## Flag

`FeatureFlag.zipHandoff`: issue 85, states off and on, dev default off, release default off, `releasedInBuild` nil, `devOnly` false. This feature has no network call and no key, so it is not a Jev flag.

`scripts/nextshot-flags.sh` gains `zipHandoff:off,on` on the `FLAGS=` line. `FeatureFlagsTests` fails when that line and the registry differ.

Turn it on with `scripts/nextshot-flags.sh set zipHandoff on`. Reset it after a test.

## Build

The zip comes from Foundation. `NetworkSourceScanTests` fails on `Process(`, `NSTask`, and `curl` in `App/Feedback`, `Packages/FeedbackKit`, and `Packages/JevKit`. So app code must not call `/usr/bin/ditto`.

Use `FileManager` to stage the folder, then `NSFileCoordinator` with `.forUploading` to write the zip, or a small Foundation zip writer if that coordinator adds `__MACOSX/` or `._` entries. Never use `ditto --sequesterRsrc`. A test lists the zip and fails on any `__MACOSX/` entry or any path component that starts with `._`.

New logic lives in FeedbackKit. New app files live under `App/Feedback/`. `project.yml` already includes that folder, so a new file there needs no project edit. Log any upstream edit in `docs/FORK_NOTES.md`.

## Files

| File | Change |
| --- | --- |
| `Packages/FeedbackKit/Sources/FeedbackKit/ZipHandoff.swift` | New. Staging, portable prompts, JPEG, size drops, zip write. |
| `Packages/FeedbackKit/Sources/FeedbackKit/PromptBuilder.swift` | Path mode and the relative-path sentence. Default stays absolute. |
| `Packages/FeedbackKit/Sources/FeedbackKit/ManifestWriter.swift` | Same path mode for the Folder line and the Codex command. |
| `Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift` | `zipHandoff` case. |
| `scripts/nextshot-flags.sh` | `zipHandoff:off,on` on the `FLAGS=` line. |
| `App/Feedback/FeedbackZip.swift` | New. Downloads write, clipboard file, Share menu, toast. |
| `App/Feedback/FeedbackStatusItem.swift` | Zip Round and Zip N Selected rows. |
| `App/Feedback/FeedbackController.swift` | Zip actions and the round key. |
| `App/Feedback/FeedbackShortcuts.swift` | `feedbackZipRound`, Option+Shift+Z. |
| `docs/agents/bundle-guide.md` | One section: a zip names files relative to the folder that holds the prompt. It holds no `jev.json` and no `jev-review/`. |

## Tests

- A portable prompt and a portable manifest hold no absolute path and no home-folder prefix. Every backtick path resolves inside the staging folder.
- A zip listing has no `__MACOSX/` entry and no `._` path component.
- The live bundle's `prompt.md` is unchanged after a zip build.
- A round over 5 MB as PNG is at or under 5 MB as JPEG, or the result records the drops and the over-size line.
- A basket of two rounds produces one folder, item ids 1.N and 2.N, and no second round folder.
- `jev.json` and `jev-review/` are absent even when the source folder has them.
- With the flag off, the menu builder adds no Zip row. This check can be a pure function the status item calls.

## Non-goals

- Rewriting the live bundle to relative paths.
- Ending the round as part of Zip.
- A save panel.
- Putting the prompt text on the clipboard at zip time.
- Shipping `jev.json` or `jev-review/`.
- A hotkey for Zip N Selected.
- A third menu row for one capture, or a start-and-end range picker.

## Open point for the plan

Confirm in the first implementation task whether `NSFileCoordinator` `.forUploading` writes `__MACOSX/` or `._` entries. If it does, the plan uses a Foundation zip writer and does not call `ditto`.
