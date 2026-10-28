# Rolling Round: requirements and discovery plan

Date: 2026-10-27. Status: reviewed discovery, Later backlog. Issue: [Rolling Round #157](https://github.com/spurs-planks-smithers/Capso/issues/157). Parent: [Chrome extension backlog #124](https://github.com/spurs-planks-smithers/Capso/issues/124). Main plan: [[2026-10-27-chrome-extension-discovery]] ([repository link](2026-10-27-chrome-extension-discovery.md)).

This document records product decisions. It does not authorize implementation, a prototype, dependencies, flag changes, or deployment. The entire Chrome extension stays outside v0.5.0. v1.0 or later remains tentative.

Scope correction, 2026-10-28: Drew requires seamless extension use with and without the Mac app. This supersedes the October 27 mandatory Mac dependency, reconnect-before-save rule, and universal Mac-loss expiry. See the [research record](../research/2026-10-28-chrome-swift-integration.md) and [draft architecture specification](../superpowers/specs/2026-10-28-chrome-extension-architecture.md) for standalone ownership and optional native handoff.

## Product purpose

Rolling Round helps a reviewer report an unexpected browser issue after it occurs. It offers a separate action to review recent history, select the relevant steps, and annotate them. The saved report can cover less than the available history.

The user may need only the last 10 seconds. That is Drew's example, not a fixed clip length or a default.

## Confirmed decisions

| Area | Requirement |
|---|---|
| Name | Rolling Round |
| Availability | Separate feature flag within the Chrome extension feature set. The flag starts off under the project's existing policy. |
| Dependency | Work with or without the Mac app, corrected by Drew on 2026-10-28. Optional native integration must preserve standalone use. |
| Arming | Reviewer explicitly arms the current tab. Site permission is approved per site. |
| Available history | Retain the last 60 seconds while tracking is active. Overwrite older unsaved data. The review default below counts recorded time and labels pause gaps. |
| Stop | Stop tracking and clear all unsaved local history, including review snapshots, extracted frames, and cached assist payloads. Saved bundles remain saved. |
| Review action | Provide a separate Rolling Round action for selecting and annotating recent history. |
| Selection | Reviewer marks the failure moment first. Then suggest setup steps and clip boundaries. Save the relevant portion, not necessarily all 60 seconds. |
| Issue suggestion | Offer an issue only when identified confidently within 1 second. Suppress later or uncertain guesses. Manual issue selection remains available throughout. |
| Review tracking | Pause live tracking and preserve current history for review. Resume after save or cancel, subject to other pause reasons. |
| Mac disconnection | Standalone capture and save stay usable. The earlier pause, mandatory reconnection, and 15-minute Mac-loss expiry are superseded on 2026-10-28. Research retention and retry for optional native transfer separately. |
| Tab switching | Pause when the reviewer leaves the armed tab. Preserve its buffer. Resume when that tab is active again, subject to other pause reasons. |
| Cross-site navigation | Pause and preserve current history. Require explicit re-arming for the new site. Request site permission when needed. |
| Assistance | Use Jev and other rapid assist tools to recommend discrete captured steps or actions. Additional tool choices remain open. |
| Jev fallback | If Jev adds no useful improvement or fails, continue normally with local suggestions and manual editing. Require no retry and show no blocking error. |
| Later enhancement | Investigate integrated Apple Intelligence in [#148](https://github.com/spurs-planks-smithers/Capso/issues/148). This is an optional Later follow-up. It does not block Rolling Round or its required local fallback. |
| Jev inputs | Sanitized action timeline, relevant diagnostics, and selected still frames. Send no GIF or video animation to Jev. |
| Network collection | Sanitized request addresses, methods, status codes, timing, and failures. Collect no headers or bodies. |
| First pilot | Local development or staging, with element matches, source context, and bug evidence checked against controlled code. |
| Recommendation priority | Within 1 second after issue selection, show useful initial local setup-step suggestions. Refine afterward with Jev. Keep review controls usable. |
| Saved result | Each Rolling Round becomes its own feedback bundle and a separate ended round. |
| Package contents | Selected animation, key frames, accepted steps, and matching diagnostics. Prefer GIF when efficient; allow compact video fallback. |
| Package priority | Keep size optimization automatic and invisible. Request no size-related input, reselection, confirmation, or retry. Preserve a seamless save flow. |
| Audio | First Rolling Round captures no microphone or tab audio. Capture visual history, actions, and diagnostics only. |
| Package size | Soft target: 5 megabytes (5,000,000 bytes) for the complete package. Automatically produce the smallest practical result and proceed normally even above the target. |
| Over-budget fallback | Automatically omit animation when compression cannot meet the target. Keep key frames, accepted steps, and diagnostics. If that result remains oversized, proceed normally with the smallest practical package. |
| Existing round | Leave any ordinary Nextshot round active. |
| Destinations | The same report supports a design conversation and a coding agent with a repository. |

Explicit start-and-stop bug recording is a separate confirmed path. Both paths belong to the broader browser feedback feature set. Bug evidence includes console errors and network summaries. Rolling Round output, no-audio scope, and the 5-megabyte target remain defined. The standalone correction replaces the earlier Mac-dependent draft lifetime. Internal buffer representation and encoder settings remain open.

## Proposed review behavior

These are planning recommendations. Drew has not approved the exact controls or data contracts.

1. Arm one approved tab and maintain its bounded rolling history.
2. Open Rolling Round. Pause live tracking and preserve the available history for review.
3. Offer an issue suggestion only when identified confidently within 1 second. Suppress late or uncertain guesses. Keep manual issue selection available throughout.
4. Let the reviewer mark the failure moment or confirm a suggested issue.
5. Show useful initial local setup-step suggestions within 1 second after issue selection. Include suggested clip boundaries. Refine afterward with Jev.
6. Let the reviewer adjust the relevant portion and annotate its evidence.
7. Automatically package the selection with animation when efficient, or use the agreed still-frame fallback. Keep key frames, accepted steps, and diagnostics. Save normally even above the soft size target. Create one ended round and keep the ordinary round active.
8. Clear the review draft after save or cancel. Resume eligible tracking in a new continuous segment. Retain only the bounded tracking history. Apply the cleanup rules below.

Pause preserves current history. Review, tab switching, and cross-site navigation impose independent tracking conditions. Resume only when each condition clears. Cross-site changes require re-arming. Mac absence cannot block browser capture or save. Replace the earlier 15-minute Mac-dependent expiry during architecture research. Stop clears all unsaved local history and invalidates pending assist results. Saved bundles remain intact.

## Recommendation approach to evaluate

Start with captured interaction events and their timestamps. Use clicks, navigation, visible state changes, and diagnostic events as candidate boundaries. This is a proposed approach, not a chosen algorithm.

Use two assistance stages. First, attempt an optional confident issue suggestion within 1 second after opening review. Suppress uncertain or late guesses. After issue selection, show useful local setup-step suggestions within another 1-second window. Refine afterward with Jev using approved data. Neither deadline blocks manual review. A useful local result identifies captured actions near the failure. It need not infer a cause. Additional tools remain unnamed until evaluated.

Keep observed actions separate from generated explanations. A click establishes an interaction. It does not establish intent, success, or cause. Every suggested step should link to its captured evidence moment. A suggested fix belongs outside the recorded action history.

The reviewer identifies the issue first and keeps control of the result. Preselect evidence-linked setup steps within the proposed excerpt. One Save accepts the displayed selection. Editing, removing a step, and changing boundaries remain optional. Exact controls need later design.

Do not change the reviewer's selected excerpt or annotations silently when a later recommendation arrives. Assistance failures need a usable local review path. These are proposed acceptance rules for the approved design.

## External references

Research method: official documentation reviewed on 2026-10-27. No tool was installed or tested. These references establish related patterns. They do not prove retrospective segmentation of a 60-second video buffer.

| Reference | Documented pattern | Relevance and limit |
|---|---|---|
| [Scribe capture](https://scribehow.com/o/_cdqCTUaQgCwJ9DRRkl4OA/page/Getting_Started_With_Scribe_Capture__LhE4a9LCQQWpvNqYebdH6w), [editing](https://support.scribehow.com/hc/en-us/sections/6852308410525-Customizing-Your-Documents) | Captured interactions produce screenshots and written steps. Steps and screenshots can be edited. | Shows that editable steps can reduce manual reporting. It does not establish video segmentation. |
| [Scribe Autocapture data](https://support.scribehow.com/hc/en-us/articles/38686531760925-What-data-does-Autocapture-collect) | Documents screenshots, clicks, and entered text. It excludes video and audio. | Distinguish an event history from a video recording. Nextshot's data policy is a separate decision. |
| [Tango capture](https://help.tango.ai/en/articles/5971654-how-do-i-start-capturing-a-workflow), [editing](https://help.tango.ai/en/collections/4063296-capturing-editing) | Actions produce screenshots and descriptions. Reviewers can edit, reorder, combine, annotate, and blur steps. | Supports action-based review as a reference. Combining steps differs from selecting a video excerpt. |
| [Jam capture](https://jam.dev/capture), [Debug Timeline](https://jam.dev/blog/launching-today-debug-timeline-you-never-have-to-write-repro-steps-again/) | Captures interactions and diagnostics. Its timeline links events to video moments. AI suggests reproduction steps. | Closest reference for evidence plus assisted reproduction. The reviewed sources do not establish editable individual AI steps or video trimming. |
| [Google animation guidance](https://web.dev/articles/replace-gifs-with-videos) | Shows that compressed video can be smaller than GIF. | Supports a compact video fallback. The cited example is not a Nextshot measurement. Compare the selected excerpt and readable quality before choosing a format. |

## Fit with Nextshot and Chrome

- Current Nextshot saves image-based captures and marks. The model needs a deliberate design for clips, time ranges, steps, diagnostics, and references between them.
- For optional native integration, `FeedbackRoundStore.start` rejects a second active round. Saving an ended Rolling Round while preserving an ordinary active round needs a dedicated reviewed save path. Standalone persistence needs a separate browser design.
- Preserve ordinary round state, K.N item identity, library visibility, agent-neutral output, zip compatibility, and existing source-text boundaries.
- Chrome's [tabCapture](https://developer.chrome.com/docs/extensions/reference/api/tabCapture) requires extension invocation. Per-site access alone does not authorize a media stream. Arming and capture startup need a later feasibility check.
- Jev currently runs only in Dev builds with separate screen-text and image consent. Future release review remains required. Rolling Round may send sanitized event details, relevant diagnostics, and selected still frames. GIF and video animation are outside that data allowance. Continuous model requests during tracking are not authorized by these decisions.
- The rolling flag, site permission, arming state, and Jev consent serve different purposes. Define their combined behavior before implementation.

Planning convention: start the one-second issue-suggestion clock when Rolling Round opens. Model startup and transfer time count toward that deadline. This is a proposed clock definition, not a measured performance claim.

## Export research and future checks

The existing native `ExportKit` supports GIF and MP4. It is a reuse candidate, not a verified Rolling Round encoder. `VideoExporter.swift` passes `ExportOptions.timeRange` to MP4, but not GIF. `GIFExporter.swift` accepts a source recording without an excerpt argument. Confirm exact trimming before reuse. Existing MP4 has special audio paths; the first Rolling Round excludes audio. Verify the selected path produces only the chosen silent excerpt.

The GIF path samples frames and owns their pixel memory through ImageIO finalization. Frame count and dimensions affect memory and encode time. No export measurement runs during this discovery work.

Proposed approach: settle the selected excerpt before encoding. Automatically choose a practical format and quality within readability and speed needs. Avoid always encoding both formats just to compare bytes. Target 5,000,000 bytes for the complete package. Use the agreed animation-free fallback when needed. If it still exceeds the target, save normally. Keep optimization and size trade-offs out of the review flow. Record pause gaps honestly.

## Routine decisions from the review

Review date: 2026-10-27. These are Codex decisions under Drew's delegation. They are planning defaults, not claims of user confirmation or implemented behavior.

| Area | Selected default |
|---|---|
| Selection controls | Use a timeline to mark the issue and a list of editable steps. Suggest boundaries from accepted setup through the failure. Final controls follow later design. |
| Fewer inputs | Preselect evidence-linked steps inside the proposed excerpt. One Save accepts the displayed selection. Require no separate acceptance click per step, title entry, or size choice. |
| Selected scope | Export only selected history. Expanding the excerpt includes earlier setup. Trimming removes out-of-range steps and diagnostics from the saved selection. Never include hidden earlier context. |
| Paused history | The buffer holds up to 60 recorded seconds, subject to internal resource limits. Preserve earlier segments while paused. Resume into a new segment. Label every real-time gap. Default to the segment containing the issue. |
| Save and cancel | Cancel discards review edits, copied frames, and assistance caches. Save does the same after successful publication. Both retain only the bounded tracking history and resume when eligible. Stop still clears all unsaved copies. |
| Review lifetime | Keep the bounded frozen draft open without an inactivity timer. Save, cancel, Stop, tab closure, browser exit, or permission loss ends it. Native-transfer retention must not expire a valid standalone draft. |
| Browser and permission loss | Tab closure, browser exit, or site-permission revocation stops collection and clears unsaved local data. Restart requires explicit arming. Partial media/diagnostic failure pauses affected collection and records its coverage. Never imply complete capture. |
| Cross-site re-arm | Old-site history remains available for review until new arming replaces it. Arming the new site starts a fresh buffer. Keep sites separate. |
| Coverage | Distinguish no observed errors from unavailable console capture. Include compact gap/coverage metadata. Unknown events stay unknown. Missing diagnostics do not block saving usable evidence. |
| Save recovery | Publish exactly one complete ended bundle using a stable draft identity. Repeated Save or reconnect delivery returns the same result. Preserve a retryable draft after save failure. Define optional native-transfer retention separately. Never expose a partial round. Preserve an ordinary native round when integration applies. |
| Structured privacy | Use an allowlist. Exclude entered field values, credentials, cookies, storage, hidden DOM content, and secrets from structured evidence. Strip URL credentials, query values, fragments, and token-like path values. Sanitize diagnostic text. |
| Visual privacy | Mask password and sensitive form fields before retaining media or sending frames. This is a design requirement. Validate coverage before support claims; automatic masking cannot promise to find every private value. |
| Assist lifecycle | Run assistance during deliberate review, not continuously during tracking. Use only the current selected evidence and existing consent. Invalidate stale results after selection changes, cancel, Stop, expiry, or permission loss. Keep local suggestions and reviewer edits. |
| Issue eligibility | Require time-aligned captured evidence for an issue suggestion. An error alone does not prove a visible failure or its cause. Suppress unsupported, late, or ambiguous guesses. Choose validation rules during design. |
| Local performance | Create the initial step list from indexed captured actions. A valid initial result can describe observed actions without inferring intent or cause. Verify usefulness and the 1-second target in a later authorized trial. |

## Remaining design work

The October 27 review resolved its product questions. The October 28 standalone scope introduces new choices in the draft architecture specification. Exact control layout, media storage, resource limits, field filters, encoder settings, diagnostic mechanisms, and pilot thresholds belong to later design. Begin with representative local/staging cases. Next test actual Claude/Artifacts previews, then live websites. Record support limits honestly. Any new scope or data allowance needs a product decision.

Drew separately approves bounded Jev help for ordinary browser annotations on 2026-10-27. It may use sanitized candidate-element details and selected still frames. Exclude sensitive fields and honor existing consent. Keep a local fallback. This does not expand Rolling Round's approved input categories.

## Backlog structure

| Record | Role | Placement |
|---|---|---|
| [#124](https://github.com/spurs-planks-smithers/Capso/issues/124) | Umbrella issue for the extension and explicit bug recording. Rolling Round #157 is its formal sub-issue. | Later, no due date |
| [#157](https://github.com/spurs-planks-smithers/Capso/issues/157) | Rolling Round requirements, discovery, and future delivery. Formal sub-issue of #124. | Later, no due date |
| This plan | Supporting decisions, lifecycle defaults, and future acceptance evidence for #157. | Linked from the main plan and #157 |
| [#148](https://github.com/spurs-planks-smithers/Capso/issues/148) | Linked optional Apple Intelligence follow-up. It blocks neither Rolling Round nor the extension. | Later, no due date |

Drew requests the formal Rolling Round sub-issue on 2026-10-27. #148 remains a linked optional follow-up, with no formal parent added. All three stay in Later without due dates. All exclude v0.5.0. v1.0 or later remains tentative. Add further implementation sub-issues only after approved scope and an authorized feasibility trial. This tracking change authorizes no build or trial.

## Proposed acceptance evidence

- A reviewer opens Rolling Round and can identify the issue immediately. An optional confident issue suggestion must arrive within 1 second. Later or uncertain guesses produce no recommendation or interruption. A manual selection cannot be replaced by a late result.
- After issue selection, useful initial local setup-step suggestions appear within 1 second. Jev may refine afterward. Suggestions cannot replace the selected issue or reviewer edits silently.
- A 10-second selection from 60 recorded seconds exports only selected history. Animation uses the exact excerpt, or the agreed still-frame fallback omits it. Key frames, accepted steps, and diagnostics stay within the selection. Pause gaps remain explicit. The bundle never silently includes the whole buffer.
- Package accounting includes animation, key frames, step text, diagnostics, and overhead. Optimize invisibly. An oversized still-frame fallback saves normally. No size prompt, forced reselection, or approval step appears.
- Step labels and suggested issue moments have timestamped evidence. Model output cannot invent an interaction or alter reviewer intent.
- Saving publishes exactly one complete ended Rolling Round. Repeated delivery creates no duplicate. A failed save keeps a retryable draft without exposing a partial round. Any ordinary active round keeps its captures, numbering, and active state.
- Tracking obeys its flag and explicit tab arming. Pause conditions compose. Browser save works without the Mac app. Optional native transfer has a separate retention and retry policy. Stop invalidates pending results. Reconnection cannot revive discarded data. Capture no audio.
- Review drafts follow the lifecycle defaults above. Save/cancel resumes into a new segment when eligible. Closure or permission revocation clears unsaved copies. Jev failure leaves local suggestions and manual editing available. Saving continues without a required retry. Late results cannot recreate discarded data.
- Pilot review measures time to the first useful suggestion, reviewer corrections, and time to a ready report. Choose representative controlled cases and pass thresholds during trial design. No measured performance claim exists yet.
- Structured evidence excludes entered values and sensitive fields. Media follows the masking requirement. Missing diagnostics carry explicit coverage metadata. No hidden earlier context or invented actions enter the saved bundle.

## Next work, planning only

Use the confirmed product decisions to settle routine implementation details. Reserve further questions for material scope, data-use, or workflow choices. Then write the product description and bounded technical trial proposal. Run no trial until Drew authorizes it. Write the implementation plan after design and feasibility evidence support it.
