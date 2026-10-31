# Changelog

All notable changes to Nextshot are listed here. The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). The numbers follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html), and stay below 1.0.0 until the commercial launch. The rules for a new number are in `docs/decisions/2026-10-25-versioning-and-releases.md`.

A pull request that changes what a person sees or can do adds one line under Unreleased. The release step moves those lines into the new version.

Capso's own history (versions 0.9.3 to 1.2.5) is not part of this file. This fork started from Capso 1.2.5.

## [Unreleased]

### Added

- Option+Shift+G captures the same screen area as your last Option+Shift+F capture, with no dragging. With no earlier area, it opens the selector.

### Changed

- A copied prompt starts with `Session Name:` and your round's title, so agent tools list each round under its own name. A round with no written instruction uses its date and time.
- A copied prompt lists your items and notes near the top and asks the agent to name its session, so sessions no longer share one name. Recent Rounds labels each round with your first instruction, and the date moves to the line below.
- Esc on a marked capture copies the marked image and saves the capture to the round with no notes, then closes the editor. The round stays open. Before, Esc with marks only stepped back.

## [0.5.0] - 2026-10-28

### Added

- Show More in Recent Rounds gives access to older rounds grouped by day, week, and month, with the same round actions.
- Submit Round to Nextshot sends a reviewed round's annotated screenshots and notes after an explicit Submit action. Clean copies and stored screen text stay on the Mac.
- Settings guides explain startup, screen access, capture preferences, and shortcut customization.
- Report a Bug and Request a Feature open the online feedback form for messages and optional attachments.

### Changed

- Fresh installations offer Launch at Login on by default. Login startup stays quiet. Disabling it in Nextshot or macOS keeps it off across updates.
- Settings use clearer pointer labels, functional shortcut groups, and compact Screen Recording help. Repository links are removed.

### Fixed

- The shortcut field's clear button clears the assigned keys while keeping the action available.
- Recent round subtitles fit app names to one line and preserve capture and selection counts.
- Clipboard Format help describes the available Escape image-copy action.

## [0.4.0] - 2026-10-27

### Added

- Website Guides with a visual first-handoff lesson, task references, local site search, and a printable shortcut sheet.
- Guarded support submission with reduced round packages, a compact note panel, and private website/email intake. Launch controls remain off pending security verification.

### Changed

- Settings focus on feedback rounds. Standalone capture, recording, translation, cloud sharing, URL automation, and updater tools stay off behind local capability flags.
- `manifest.md` lists the annotated images under Images and no longer holds a Codex command, so any AI agent reads a bundle the same way. Older bundles keep their old section.

## [0.3.0] - 2026-10-26

### Added

- The editor opens on the red dot tool, so the first click drops dot 1 with no key first. It restores your earlier tool when it closes.
- Option+Shift+E (End Round) copies the round prompt, as Option+Shift+R does.
- The active round leads the Recent Rounds list, marked with a green dot.
- The Start Feedback Round and End Feedback Round actions in Shortcuts. The old Session actions keep working in saved Shortcuts.
- A double-click on Nextshot in the DMG installs it over a running copy. It quits the old copy, replaces it, opens the new one, and ejects old installer disks.
- The DMG says "Nextshot is up to date" when its copy is not newer, with Install Anyway for a move back.
- A round saved by a newer Nextshot stays untouched. The Nshot menu hides it and says how many it hid, so an older copy never drops fields it does not know.

### Changed

- Version numbers are plain numbers such as 0.3.0, not dates.
- The help box moved to the bottom right, so it no longer covers the Nshot menu.
- Toasts stay three times longer.
- The newest capture comes first in each Recent Rounds submenu.
- The newest build wins when two copies start: the higher build number, whatever its version text.

### Fixed

- The help box stays on its own display and returns after a failed selection.
- The DMG install no longer asks a second time to open Nextshot.

## [0.2.0] - 2026-10-24

Shipped as 2026.10.24, build 524. Back-filled on 2026-10-25.

### Added

- Round keys: Option+Shift+C copies the last capture prompt, R copies the prompt and ends the round, O opens the round folder, and E ends the round. They work only while a round is active.
- The five Nextshot keys appear in Settings > Shortcuts. A key another action uses is refused.
- A green dot on the menu bar mark while a round is active.
- Copy Prompt and End Round: copying the round prompt ends the round, and Resume in Recent Rounds reopens it.
- nextshot.dev, the download page with the intro video.

### Fixed

- One round end at a time, no round end under an open capture, and no two actions on one key.
- The help box returns after a capture that never starts.
- The start key panel keeps its view when shown again.

## [0.1.0] - 2026-10-22

Shipped as three builds labeled 2026.10.22. Back-filled on 2026-10-25.

### Added

- Feedback rounds. Option+Shift+F selects a screen area. Mark it with numbered red dots, boxes, arrows, and text. Answer one question per dot. Nextshot copies a prompt that points an AI coding agent at the annotated image.
- The Nshot menu bar item with a list of recent rounds, Resume Round, and Copy Last Capture Prompt.
- A bundle folder per round, with a manifest, a prompt, and a `feedback.json` file for scripts.
- The Nextshot mark on the menu bar.
- A notarized DMG and zip.

### Fixed

- Only one copy of Nextshot runs at a time.
