# Settings guide and feature gates

Date: October 27, 2026. Status: implementation approved. Native code passes review and its existing checks. Guide media and release verification remain in progress. Drew selects feedback rounds first for the next release. Detailed source catalog: [[2026-10-27-settings-catalog]].

### Outcome

Give a new user a short Settings section focused on capture, notes, and handoff. Keep a complete internal catalog for maintainers. Put optional standalone tools behind local feature flags before documenting the streamlined release.

The current code has eight visible Settings tabs and a ninth hidden Cloud Share tab. Proposed default: General, Permissions, Screenshots, Shortcuts. Keep the existing native style and exact tab labels for this first pass. Do not redesign the window before checking a running review build.

### Confirmed scope and evidence limits

- Drew chooses feedback rounds first. Standalone screenshot tools become optional behind a flag.
- Drew approves executing the full plan on October 27. Implementation, signed build review, matching release, and guide publication are in scope.
- Source reviewed at `188ee7d`, `VERSION` 0.3.0. A source checkout is not proof of the released binary's behavior.
- Baseline capture is resolved. The running Dev copy is under the original build folder, not Applications. Its eight visible tabs are inspected and captured. New-build review remains.
- The existing guide design uses Starlight, Inter, Step, GuideImage, Shortcut, and task-based sidebar groups. Reuse them. The native app uses its existing SwiftUI SettingGroup, SettingCard, and SettingRow views.
- No usage telemetry proves a feature is unused. Recommendations reflect the selected product scope and source dependencies.

### Next release: what stays visible

| Tab | Default visible content | Detail placement |
| --- | --- | --- |
| General | Launch at Login, version, support and source links, local diagnostics | Put troubleshooting details after daily-use controls. Remove the upstream Follow on X row. |
| Permissions | Screen Recording and Refresh | Show other permission rows only when their consuming tool is enabled. Do not request extra permissions for rounds. |
| Screenshots | Show Cursor and Clipboard Format | Keep Clipboard Format independently visible. It controls Escape copy even when an old Clipboard Content value is File Path. |
| Screenshots, Advanced | Timestamp options, capture preset options | Use progressive disclosure. Preserve saved values. These are working shared capture preferences, so they do not need individual feature flags. |
| Shortcuts | The five Nextshot actions first | Keep center-selection detail under Advanced. Hide standalone rows and their fixed references when their capability is off. |

General's Show Menu Bar Icon controls the extra capture menu, not Nshot. Hide it with standalone capture tools. If those tools are enabled later, rename it to identify that extra menu and update the confirmation text. History settings must say Screenshot History. They do not retain or delete round folders.

### Recommended flags and release defaults

Names below are proposals. Each new top-level flag starts off in dev and release. Review with a local dev override. Leave existing Jev, zip, and support policies intact.

| Proposed flag | Release default | Gate together | Reason |
| --- | --- | --- | --- |
| `standaloneCapture` | Off | Ordinary screenshot/pin/editor/History entry points; extra capture menu; ordinary preview, save, export, and History controls; matching shortcuts and URL actions | Keeps the default product focused on feedback rounds. Shared area selection, annotation, round image copy, and local OCR remain available. |
| `recordingTools` | Off | Recording tab, recording export controls, recording/camera entry points, shortcuts, camera/microphone/input permission rows | Rounds do not use video, camera overlays, or recording effects. |
| `translationTools` | Off | Translation UI, shortcuts, URL actions, selected-text access, provider resolution, key reads, and transports | Optional task outside feedback. A saved external provider must not bypass an off flag. |
| `cloudShare` | Off | Tab, wizard/test/reset actions, share controls, share coordinator creation, automatic upload, cloud shortcuts, URL commands | The hidden sidebar tab currently leaves runtime upload paths available. |
| `automationURLs` | Off | Incoming URL actions, permission prompt, General controls, command sheet | Advanced standalone integration. Keep round App Intents as a separate supported path. |
| `automaticUpdates` | Off | Updater creation/startup, update UI, menu actions, and background/manual checks | No configured Nextshot feed. Existing issue 4 owns the future feed and update delivery. Keep manual DMG updates. |

Do not gate all of CaptureCoordinator, AnnotationKit, or OCRKit. Round capture uses shared code. Gate standalone actions where they enter the shared system. Standalone OCR follows `standaloneCapture`; round text extraction does not. If translation is later enabled, explicitly restrict runtime provider resolution to reviewed providers. A one-option picker alone is insufficient.

Quick Access becomes hidden with standalone capture. Export appears only when an enabled optional tool needs it. Filter video quality by recording capability and screenshot/file controls by standalone capture capability. Do not add a feature flag per preference, a public flag editor, or remote configuration.

### Capability dependencies and lifecycle

Use a fork-owned capability policy to resolve these combinations once at launch. Changes through the flag script require a normal quit and reopen. Do not terminate active work to apply a flag. Every view and command reads that same launch policy. This avoids a visible menu disagreeing with a running coordinator after an external preference change.

| Capability | Required flags | Mixed-state behavior |
| --- | --- | --- |
| Ordinary screenshots, pins, History, file opening, standalone OCR | `standaloneCapture` | Shared round selection and OCR stay available regardless. |
| Recording and camera | `standaloneCapture` plus `recordingTools` | Recording on alone exposes nothing. |
| Translation | `standaloneCapture` plus `translationTools` | Translation on alone exposes nothing and reads no provider key. |
| Screenshot cloud sharing | `standaloneCapture` plus `cloudShare` | Cloud on alone creates no share coordinator. |
| Recording cloud sharing | `standaloneCapture`, `recordingTools`, `cloudShare` | All three must be on. |
| Incoming automation URL | `standaloneCapture`, `automationURLs`, and the action's required flags | A URL cannot bypass the target capability. Round App Intents remain separate. |
| Updates | `automaticUpdates` | Independent of the optional capture tools. |

Each proposed flag allows off/on, uses `devOnly: false`, starts off in both channels, and has `releasedInBuild: nil`. Release overrides remain possible for local review. Do not use the Jev sub-flag helper, which makes children dev-only. After plan approval, create a Settings implementation issue and use its real number for these registry entries. Never use issue 0. Update existing registry/script checks.

Keep shared coordinator objects if required by existing references. Gate their optional side effects separately. With standalone capture off, stop History retention cleanup. With recording off, do not run interrupted-recording recovery. Preserve saved recordings for later recovery after re-enabling. Gate Finder image-open events, clipboard edit actions, menu/camera actions, URL dispatch, shortcuts, and optional App Intents. Disabled file opening should explain that the optional tool is unavailable. Never route a file into a feedback round silently.

### Existing behavior that needs care

| Finding | Evidence | Planned treatment |
| --- | --- | --- |
| Hidden Cloud Share can restore saved configuration | `App/Sources/AppDelegate.swift`, `makeShareCoordinator`; ordinary capture and recording upload branches | Gate coordinator creation and all share entry points before claiming the feature is disabled. |
| Saved external translation can still resolve | `OCRSettingsView.swift` Apple-only picker; `TranslationCoordinator.swift` provider dispatch | Off must block service resolution and requests. Preserve old provider values and Keychain items. |
| Update controls imply a working service | No SUFeedURL in app/build sources; issue 4 confirms manual updates | Hide and stop updater initialization under the capability flag. |
| Core round shortcuts follow 21 standalone actions | `ShortcutSettingsView.swift` | Put Nextshot first and filter rows by enabled capability. |
| Clipboard Format hides under an unrelated setting | Screenshot Clipboard Content controls visibility, while round Escape always copies an image | Decouple visibility in round-focused Settings. Retain its selected format. |
| Timestamp changes round pixels | CaptureCoordinator applies it before feedbackSink | Keep off by default and explain its effect in Advanced. Do not silently reset an existing choice. |
| Custom preset validation accepts nonpositive dimensions | Add button and model append check only integer parsing | Fix positive-dimension validation before recommending custom presets. No fix is made in this planning session. |
| Camera/Microphone Open label calls request again | PermissionSettingsView and PreferencesViewModel | Repair before exposing those tools again. Keep the separate system-settings icon documented internally. |
| Older instructions omit TIFF clipboard support | AGENTS copy description differs from current enum and image encoder | October 27 source/doc discrepancy. Confirm intended formats before changing instructions or public copy. |

Read full issue histories for [Feature flags: local registry with dev and release defaults](https://github.com/spurs-planks-smithers/Capso/issues/35), [Jev sub-feature flags: every feature gets sub-flags, all off](https://github.com/spurs-planks-smithers/Capso/issues/94), [Self-serve updates: Sparkle with a Nextshot feed](https://github.com/spurs-planks-smithers/Capso/issues/4), and [Menu bar: hide the standard capture icon by default (one Nshot icon)](https://github.com/spurs-planks-smithers/Capso/issues/8). Those records establish the existing registry, completed sub-flags, deliberate manual updates, and single-menu default. This review does not reopen those decisions.

### Learning guide structure

Add a Settings sidebar group after Work with rounds and before Quick answers. Give the overview a matching home task card. Keep Your first handoff short. Add only a link from that guide to settings when customization becomes relevant.

| Planned page | Reader outcome | Content |
| --- | --- | --- |
| `settings/index.mdx`, Settings overview | Know what needs attention | State that default settings support a full round. Show how to open Settings. Map the four tabs. Link deeper pages and explain round storage. |
| `settings/general.mdx`, Startup and support | Start reliably and find help | Login behavior, installed version, local logs, crash reports, bug/feature/source links. Explain that opening a link does not submit anything. |
| `settings/permissions.mdx`, Screen access | Give only required access | Explain the macOS Screen Recording name, Dev/release grants, status, Open, and Refresh. Link installation and troubleshooting instead of repeating them. |
| `settings/capture.mdx`, Capture and image copy | Change capture behavior safely | Cursor and Escape image format first. Advanced timestamp and preset sections below. Explain that capture settings do not configure round prompt copy. |
| Existing `shortcuts.mdx` plus Settings link | Set the keys for rounds | Five round actions, active-round limits, duplicate-key refusal, cancel/remove behavior, center-selection key. Preserve the printable sheet. |

Each page starts with the result, then one real Settings screenshot, then short task steps. A compact reference gives each visible control's default, effect, and when to change it. Optional detail uses a disclosure or a lower section. Keep exact UI labels. Do not make users read a giant cross-product settings table to complete their first round.

The internal catalog retains all nine sections, including hidden tools. Public Guides cover only released behavior with default flags. When an optional capability becomes supported by default, add its small reference page in the same release. Do not publish disabled-feature instructions or a feature flag command in general Guides.

### Implementation order

| Step | Files or area | Concrete work and exit condition |
| --- | --- | --- |
| 1. Verify baseline | Running release and Dev builds; catalog | Capture each existing tab and conditional state. Confirm source differences before editing UI. Use safe demo data. Record actual version/build. |
| 2. Gate optional tools | `Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift`, `App/Feedback/Flags.swift`, new fork helper files, `scripts/nextshot-flags.sh` | Reuse local channel defaults and off/on states. Decide shared capability policy once. Add narrow hooks at UI and runtime entry points. |
| 3. Simplify Settings | Preferences tabs, shortcut rows, permission rows, coordinator setup | Apply the four-tab default. Preserve stored preferences and files. Handle a hidden selected tab by routing to General. |
| 4. Review the running build | Signed Nextshot Dev | Check all default-visible controls. Exercise a complete round, Escape copy, resume, and prompt copy. Confirm optional actions do not run through old shortcuts or URLs. |
| 5. Write Guides | `site/guides/src/content/docs/settings/`, `astro.config.mjs`, home index, shortcut/install/troubleshooting links | Author the overview and detailed pages after the visible app is settled. Review current 0.3.0 instructions separately from the future default. |
| 6. Capture guide media | `site/guides/public/media/settings-*`, `media-sources.json` | Capture real released screens and applicable conditional states. Inspect every image. Record source version/build per asset. |
| 7. Validate and stage | Guides build, existing site checks, `site/deploy.sh --stage-only` | Inspect every new page on desktop and phone. Check links, search, keyboard focus, and image enlargement. Stage exact artifact for release publication. |

Every upstream hook edit gets a `docs/FORK_NOTES.md` entry. A user-facing behavior change gets an Unreleased changelog line. Add no framework or broad new test suite. Update existing relevant checks where the behavior changes. Keep a short manual review matrix for the running app.

Release order: verify Dev, cut and install the matching release, capture release screenshots, set reviewedFor, build and stage Guides, then publish. Guide drafts stay unpublished until that app release exists. Keep the 0.3.0 guide accurate while the next release is prepared.

### Verification matrix

| State | Required observation |
| --- | --- |
| Fresh defaults, optional flags off | Four visible tabs. Only relevant permission rows and round shortcuts. No optional shortcut registration or service initialization. |
| Existing preferences, optional flags off | Old cloud/translation/update/automation choices cannot start those tools. Existing rounds, History files, keys, and preferences remain intact. |
| Flag combinations in Dev | Master-off states expose no child tools. Enable each supported combination and confirm its UI/runtime agree. |
| Flag changed while app runs | Current launch policy stays consistent. After normal quit/reopen, off removes entry points, shortcuts, startup work, and service requests. Files and saved preferences remain intact. |
| Round selection, marks, notes, end, resume | Existing round behavior and files stay correct. Local OCR and annotation still run. |
| Escape from an unmarked capture | Copies the selected image format. Does not save a capture or end the round. |
| Timestamp and preset controls | Values persist and affect the expected image/selection only. Check extreme supported values and reject nonpositive custom sizes. |
| Guide and release mismatch | Do not raise reviewedFor to an unchecked version. Do not label local Dev screenshots as release evidence. |

### General backlog issue

Created [Adopt capability flags across Nextshot](https://github.com/spurs-planks-smithers/Capso/issues/118) as an unscheduled enhancement with exactly one severity label, sev-polish. The core task remains possible while this policy is absent. Reuse the completed registry from issue 35. This is broader than the next release's Settings cleanup. Acceptance covers capability ownership, UI/runtime consistency, local overrides, state preservation, release review, documentation, and flag removal rules. No tracking kit or milestone is added.

### Approval boundary

Drew approves this implementation plan on October 27. Live app access must work before any claim that the simplified Settings or guide screenshots are verified. Publication uses the existing release/site process after the reviewed app behavior is available.
