# Nextshot Chrome extension: research and discovery plan

Date: 2026-10-27. Owner: Drew. Status: backlog discovery. Implementation is not authorized.

Scope correction, 2026-10-28: Drew requires seamless Chrome use both with and without the Mac app. This supersedes the October 27 Mac-required scope and mandatory reconnection rules. Keep all issues in Later. The [research record](../research/2026-10-28-chrome-swift-integration.md) and [draft architecture specification](../superpowers/specs/2026-10-28-chrome-extension-architecture.md) guide the revised direction.

## Release boundary

- Excluded from v0.5.0.
- Candidate for v1.0 or later. This is an earliest planning horizon, not a release commitment or a launch dependency.
- Keep the issue in the existing Later milestone. Assign no due date.
- Do not scaffold an extension, install packages, run a prototype, change app code, enable flags, or deploy anything under this plan.
- Complete requirements interviews before writing an implementation-ready specification. Drew must separately authorize any technical trial or build.

## Request and evidence

The supplied conversation shows a Nextshot user who installed the Mac app. The user spends substantial time in Claude design and asks for browser element context.

> I've downloaded and installed it, but, I spend a ton of time in Claude design right now. What I think would be outstanding is if you made it a chrome extension too so it could pull the html element values too.

Source: screenshot supplied by Drew on October 27, 2026. The quote preserves its request. The local source image is outside this documentation PR. Its wording is not an approved specification.

## Confirmed requirements

| Topic | Confirmed answer | State |
|---|---|---|
| Product | General Nextshot browser companion. Release on Mac first; keep the browser core portable. | Mac-first scope confirmed by Drew on 2026-10-28 |
| Primary value | Help an agent find the exact element by attaching element details to marked feedback | Confirmed by Drew |
| Handoff destinations | One capture supports both a design conversation and a coding agent in a repository | Confirmed by Drew |
| Installation | Work with and without Nextshot. On Save, quietly start the correctly paired installed app and import automatically. Browser save remains available if native delivery fails. | Confirmed by Drew on 2026-10-28; supersedes the October 27 Mac-required scope |
| Capture workflow | Keep area selection, annotations, and notes. The extension adds element details. | Confirmed by Drew |
| Element lookup | Try to detect element details from annotation locations | Confirmed by Drew |
| Location result | Identify the exact page element; include source file details when available | Confirmed by Drew |
| Ambiguous matches | Offer a quick choice. The reviewer chooses the element. | Confirmed by Drew |
| Site permission | Approve each site once. Later captures on that site retain the current flow. | Confirmed by Drew |
| Jev assistance | Bounded candidate details and selected still frames, with consent and a local fallback. Include standalone Jev through an authenticated service for invited pilot users. Nextshot funds a bounded allowance. | Payload confirmed on October 27. Service, audience, and funding confirmed on 2026-10-28. |
| Surfaces | Claude Design and Artifacts previews, local development and staging, and live websites all matter | Confirmed by Drew |
| Validation order | Local development/staging proves the first pilot. Claude previews and live websites remain in scope. | Confirmed by Drew on 2026-10-27 |
| Bugs | Record the bug with observable errors and permitted request summaries. Label gaps. The first extension excludes debugger access. | Diagnostic scope confirmed by Drew on 2026-10-28 |
| Network collection | Sanitized addresses, methods, status codes, timing, and failures. No headers or bodies. | Confirmed by Drew |
| Explicit recording | Reviewer starts before reproducing the bug and stops when finished | Confirmed by Drew |
| Rolling Round | Separate feature flag; retain the last 60 seconds for unexpected bugs | Confirmed by Drew |
| Rolling Round review | Separate action. Identify the failure moment first, then suggest setup steps and clip boundaries. The result can be shorter than 60 seconds. | Confirmed by Drew |
| Rolling Round issue suggestion | Recommend only when identified confidently within 1 second. Suppress late or uncertain guesses. Manual selection stays available throughout. | Confirmed by Drew |
| Rolling Round pause | Review, tab switches, and cross-site navigation pause tracking. Preserve history. Mac absence must not block browser use. The earlier mandatory reconnection and 15-minute Mac-loss expiry need replacement in the revised architecture. | Corrected for standalone use on 2026-10-28 |
| Rolling Round assistance | Useful local setup suggestions within 1 second after issue selection. Jev may refine. If Jev fails or adds no improvement, continue with local suggestions. No blocking retry. | Confirmed by Drew |
| Rolling Round Jev inputs | Sanitized action timeline, relevant diagnostics, and selected still frames. No GIF or video animation sent to Jev. | Confirmed allowance retained across export formats |
| Rolling Round save | Create a separate ended feedback round. Keep any ordinary round active. | Confirmed by Drew |
| Rolling Round package | Animation, key frames, accepted steps, and matching diagnostics. Prefer efficient GIF or compact video. Automatically omit animation if needed. If still oversized, save normally with the smallest practical package. | Confirmed by Drew |
| Rolling Round audio | First version captures visual history, actions, and diagnostics only. Capture no microphone or tab audio. | Confirmed by Drew |
| Rolling Round budget | Soft target: 5 megabytes for the whole package. Optimize automatically and invisibly. Produce the smallest practical result and proceed normally even above target. Request no size-related action. | Confirmed by Drew |
| Rolling activation | Reviewer explicitly arms tracking for the current tab | Confirmed by Drew |
| Unsaved history | Overwrite older data. Stop clears all unsaved local history, including review copies. Saved bundles remain intact. | Confirmed rule applied to all unsaved copies |
| Delivery | v0.5.0 excluded; v1.0 or later is tentative | Confirmed by Drew |
| Permission to build | No implementation or execution | Confirmed by Drew |

## Value to validate

Proposed job: select the thing that needs a change, explain the change, and give the agent enough evidence to find the correct target.

Expected benefits remain hypotheses: fewer clarification turns, less manual element inspection, fewer changes to the wrong component, and easier bug reproduction. Measure these against Nextshot's current screenshot-and-note flow. Do not claim savings before a comparison.

## External research spike

Method: review official product documentation and Chrome platform documentation on 2026-10-27. No competitor was installed or tested. Product claims below are documented capabilities, not measured results.

| Reference | Documented behavior | Implication for Nextshot |
|---|---|---|
| [Marker.io](https://help.marker.io/en/articles/6495644-browser-extensions) | Browser screenshots and comments feed project tools. Its injected widget can collect replay, console, and network evidence. | Browser feedback is established. Detailed debugging adds collection and setup scope. |
| [BugHerd](https://bugherd.com/visual-design-feedback-tool) | Pins feedback to page elements and includes element/CSS selector context with screenshots. | Element identity plus visual evidence is a useful baseline. A full task board is separate scope. |
| [Jam](https://jam.dev/docs/introduction), [Debug Timeline](https://jam.dev/blog/launching-today-debug-timeline-you-never-have-to-write-repro-steps-again/), [agent handoff](https://jam.dev/resolve) | Connects recorded interactions and diagnostics to video moments. AI suggests reproduction steps. | Reference for Rolling Round assistance. Captured events and generated narrative remain distinct. |
| [Tango capture](https://help.tango.ai/en/articles/5971654-how-do-i-start-capturing-a-workflow), [editing](https://help.tango.ai/en/collections/4063296-capturing-editing) | Captured actions become editable screenshot-based steps. | Reference for fast step review. Retrospective video segmentation is not established. |
| [Scribe editing](https://support.scribehow.com/hc/en-us/sections/6852308410525-Customizing-Your-Documents) | Workflow steps can be edited, combined, and annotated. | Supports discrete-step review. It does not prove a rolling-video implementation. |
| [Agentation output](https://www.agentation.com/output), [FAQ](https://www.agentation.com/faq) | Structured agent feedback includes selectors, classes, bounds, component context, and optional computed styles. Development mode can expose source locations. Requires app integration. | Closest reference for the confirmed goal. Source mapping depends on the host app and build. |
| [React Grab](https://github.com/aidenybai/react-grab) | Copies selected element context for coding agents. Examples include HTML and component/source context. | Useful reference for a compact payload. Universal extension coverage is not verified by this spike. |
| [Claude Design](https://support.claude.com/en/articles/14604406-claude-design-admin-guide-for-team-and-enterprise-plans) | Offers inline comments and code handoff. Its previews run in sandboxed frames on a separate content domain. | Interview why native comments are insufficient. Frame access is a first feasibility question. |

Confirmed scope combines annotation-based element context and explicit bug recording with console errors and network activity. Add short rolling history as a separately flagged feature for unexpected bugs. Its flag starts off under the existing feature-flag policy. A full issue tracker, general browser control, and automatic code edits remain deferred.

Target drift: Anthropic's [migration guide](https://support.claude.com/en/articles/17440474-move-from-standalone-claude-design-to-claude) says standalone Claude Design closes December 14, 2026. Confirm the requester's actual browser surface. A future trial must include the replacement Artifacts experience.

## Technical findings and limits

| Area | Established fact | Planning consequence |
|---|---|---|
| Access | Chrome [activeTab](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab) grants temporary access after user action. Script injection also needs scripting permission. | Prefer deliberate capture over access to every page. Additional frame access may need optional host permissions. |
| Native hotkey and access | Chrome documents extension actions and extension commands as activeTab gestures. A native Mac hotkey is not a documented grant. [Permissions API](https://developer.chrome.com/docs/extensions/reference/api/permissions) supports optional site access requested through a user gesture. | Select the site-permission strategy. The Mac screen recording grant does not replace Chrome site access. |
| Embedded previews | [Content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts) use frame URL rules. Setting all_frames does not grant permission for every frame. Claude documents a separate preview domain. | Verify actual preview URLs, permissions, sandbox behavior, and inner-element selection in a separately approved trial. Do not promise Claude compatibility yet. |
| Screenshots | [captureVisibleTab](https://developer.chrome.com/docs/extensions/reference/api/tabs#method-captureVisibleTab) captures the visible active tab. Its screenshot access differs from script access. | Distinguish a screenshot-only result from element enrichment. Whole-page capture requires separate work. |
| Source access | Content scripts share the document structure but have an isolated JavaScript environment. | Rendered HTML does not guarantee access to React state, source files, or source maps. |
| Shadow trees | Chrome's [dom API](https://developer.chrome.com/docs/extensions/reference/api/dom) can return open or closed shadow roots. | Do not call closed roots universally inaccessible. Set scope and verify traversal in the chosen extension context. |
| Native integration | [Native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) needs an installed host, a host manifest, an extension permission, and allowed extension IDs. | A Mac companion needs installation and update design. Standard input/output avoids a local socket server. |
| Bug video | Chrome [tabCapture](https://developer.chrome.com/docs/extensions/reference/api/tabCapture) requires extension invocation. An [offscreen recorder](https://developer.chrome.com/docs/extensions/how-to/web-platform/screen-capture) can own the stream. | Site approval alone is insufficient. Compare Chrome recording with native recording in a later approved trial; preserve explicit Start/Stop and define rolling activation. |
| Network diagnostics | [webRequest](https://developer.chrome.com/docs/extensions/reference/api/webRequest) observes request events and needs access to destination and initiator. It exposes no response-body retrieval API. | Approving the top-level site may not cover its cross-origin requests. Payload depth and missing-event reporting shape the permission design. |
| Console and deep diagnostics | [debugger](https://developer.chrome.com/docs/extensions/reference/api/debugger) plus [DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/tot/Network/) can provide richer data with separate permission. Opening DevTools can terminate attachment. Page hooks can miss events. | Choose the capture mechanism after diagnostic scope is set. Test frames, workers, disconnects, buffering, and DevTools coexistence before promising coverage. |
| Distribution | Chrome's [data policy guidance](https://developer.chrome.com/docs/webstore/program-policies/user-data-faq) requires disclosure for local data handling too. [Manifest V3 policies](https://developer.chrome.com/docs/webstore/program-policies/mv3-requirements) limit remote executable code. | Plan publication, permissions, disclosures, and packaged code after scope approval. Recheck policies before release. |
| Animation export | [Google guidance](https://web.dev/articles/replace-gifs-with-videos) shows video can be smaller than GIF. Existing `ExportKit` supports both, but its GIF dispatch omits the selected time range. | Reuse is conditional on exact excerpt handling and measured export cost. Prefer GIF when efficient; use compact video fallback as needed. |

## Architecture choice and alternatives

| Option | What it provides | Main trade-off |
|---|---|---|
| Browser-owned capture and export | Selection, notes, context, and handoff without the Mac app | Required by the October 28 direction. Keep the browser implementation lightweight. |
| Optional Mac companion integration | Browser captures and context join native Nextshot rounds. Native messaging is a candidate transport. | Must improve the experience without becoming a prerequisite. Host installation and channel routing need design. |
| Instrumented app integration | A page package supplies component and source context on sites the team controls | Richer development context. It cannot cover arbitrary third-party sites by itself. |

On 2026-10-28, Drew requires standalone browser use plus optional seamless Mac integration. The earlier companion-only choice is superseded. Preserve area selection, annotations, and notes in each mode. Infer element context from saved annotation locations. Include reliable source locations when available. Research transport, storage ownership, and reuse before choosing the architecture.

## Proposed payload to review

The Document Object Model (DOM) is the browser's tree of page elements. Cascading Style Sheets (CSS) describe their appearance. HTML attributes, visible text, computed CSS, and live form values are separate data categories.

| Category | Candidate contents | Current decision |
|---|---|---|
| Reviewer intent | Note, mark number, requested result, optional reproduction steps | Preserve separately from page data |
| Element identity | Match annotation locations to page elements; attach selectors, safe attributes, visible text, ancestry, and role | Annotation-driven lookup confirmed. Use bounded fields; exclude entered values and sensitive attributes. |
| Visual evidence | Screenshot, selected bounds, viewport, scroll, zoom, pixel scale, capture time | Proposed core; capture extent needs approval |
| Page context | Sanitized page/frame address, title, route, browser version | Proposed; private path and URL handling need approval |
| Style context | Small set of computed fonts, colors, sizes, and spacing | Optional; do not collect all styles by default |
| Source context | Component names and source location when reliably available | Include available source file details, confirmed; never invent a match |
| Bug evidence | Recording, console errors, and network request summaries with shared timestamps; actual/expected result and steps add context | Summaries exclude headers/bodies. Record unavailable coverage. Rolling Round retention and export defaults follow its focused plan. |
| Rolling buffer | Last 60 recorded seconds for the armed tab. Preserve pause gaps explicitly. Standalone browser save must work without Mac reconnection. | Research browser ownership and revise the earlier Mac-dependent retention rule. |
| Sensitive content | Form values, passwords, tokens, cookies, hidden nodes, storage, network headers and bodies | Exclude sensitive fields and entered values from structured evidence. Mask sensitive form fields in media. Validate sanitization before a support claim. |

A selector is evidence for locating an element, not a durable ID. Dynamic pages, generated classes, repeated labels, and component rerenders can invalidate it.

## Fit with the current code

- `Packages/FeedbackKit/Sources/FeedbackKit/FeedbackModel.swift` uses schema version 1. Captures hold images, pixel dimensions, time, app/title text, notes, OCR, and marks. There are no browser element fields.
- `FeedbackRoundStore.swift`, `ManifestWriter.swift`, and `PromptBuilder.swift` own saving and agent handoff. Browser context must remain optional for native-only captures.
- `ScreenText.swift` already bounds and cleans screen data. HTML, selectors, attributes, URLs, and logs need an explicit untrusted-data boundary too. Reviewer instructions remain authoritative.
- Existing copied prompts are agent-neutral. Browser enrichment must preserve that rule and K.N item identity.
- Jev currently runs only in Dev builds with content-specific consent. Rolling Round permits sanitized timeline/diagnostic data and selected still frames. Ordinary ambiguous annotations permit sanitized candidate-element details and selected still frames, confirmed on 2026-10-27. Existing consent applies. GIF/video stays excluded. Filtering and release review remain design work.
- `App/Feedback/Capabilities.swift` gates URL automation. A companion must not assume it is enabled or send large page data in a URL.
- Native recording is gated by `recordingTools`, which also requires `standaloneCapture`. Plan a specific browser-recording capability or an approved reuse of that path. The Chrome extension requirement does not itself enable upstream recording tools.
- `Packages/JevKit/Tests/JevKitTests/NetworkSourceScanTests.swift` enforces narrow network exceptions. Add no general local server or outbound path silently.
- Any optional native integration belongs in fork packages with small `App/Feedback/` hooks. `FeedbackRoundStore.start` rejects a second active round. Plan a separate ended-round save path for Rolling Round while preserving the ordinary active round. Review schema, zip, library, and support-export compatibility.

## Plan and decision gates

These are proposed milestones of this investigation, not new GitHub milestones. Only research and documentation run now.

| Step | Work | Exit evidence | Authorization |
|---|---|---|---|
| 1. Research | Compare official references and inspect existing bundle boundaries | This research record with source links and limits | Complete |
| 2. Interview | Establish audience, workflow, destination, payload, bug scope, and privacy | This review is complete. Revisit only material gaps from new evidence. | Complete for this review |
| 3. Product definition | Define one end-to-end first slice, exclusions, fallback, and success checks | Drew approves the written scope and architecture choice | Not approved |
| 4. Feasibility trial | Later, test actual Claude frames, owned sites, element mapping, and the chosen handoff | Working capture evidence; an honest support matrix; bounded effort estimate | Requires separate approval; do not run now |
| 5. Implementation plan | Specify exact files, payload contract, compatibility, and required existing checks | Reviewable task plan derived from approved requirements and trial evidence | Blocked on prior decisions; no implementation now |
| 6. Build and pilot | Later, build the approved slice and compare it with screenshot-only feedback | Drew reviews actual results and decides release placement | Not authorized; excluded from v0.5.0 |

## Future acceptance cases to agree

- Selected element, screenshot, mark, and note refer to the same page state. Navigation or a rerender cannot silently pair unrelated evidence.
- Convert saved image-mark positions to the browser page coordinates. Account for crop origin, viewport, scroll, zoom, pixel scale, and frame position. Use matching capture-time evidence or detect a stale page.
- Set target rules for dots, arrow tips, boxes, and other marks. Ambiguous or missing elements must not become false exact matches.
- An agent locates the intended element on agreed real tasks. Measure clarification turns, wrong-target edits, and time to a correct target against the current flow. Drew sets the pass threshold.
- Previews, owned local/staging sites, and live websites have explicit supported and unsupported cases. Blocked frames return an honest limitation or an approved screenshot-only fallback.
- Zoom, display scaling, scrolling, nested frames, repeated elements, canvas content, and shadow trees do not produce false element matches.
- A page's text and attributes cannot become reviewer instructions. Exported context is bounded. Missing source data stays unknown.
- Sensitive fields and private URL values follow the approved exclusion policy. The reviewer can inspect what a handoff contains.
- If native handoff is chosen, a missing host, app shutdown, duplicate retry, version mismatch, and simultaneous round capture have explicit outcomes.
- Explicit bug recording covers the period between the reviewer's start and stop. Synchronize video, console errors, network events, and annotations. Mark unavailable diagnostics honestly.
- Rolling Round has its own flag. Arm the current tab; retain 60 recorded seconds. Review pauses tracking. Identify the issue first, with an optional quick confident suggestion or silence. Recommend setup steps and clip boundaries. Save exactly one complete ended round. Preserve the ordinary active round. Apply the lifecycle and evidence defaults below.

## Review decisions and remaining work

Review date: 2026-10-27. The routine defaults below are Codex recommendations under Drew's delegation. They do not change confirmed product decisions or authorize execution. Detailed rules: [[2026-10-27-rolling-round-discovery]] ([repository link](2026-10-27-rolling-round-discovery.md)).

| Topic | Decision |
|---|---|
| Tracking structure | #124 is the umbrella issue. [Rolling Round #157](https://github.com/spurs-planks-smithers/Capso/issues/157) is its formal sub-issue. Apple Intelligence [#148](https://github.com/spurs-planks-smithers/Capso/issues/148) is a linked optional follow-up. All stay in Later. |
| Split timing | Track Rolling Round separately under #124, as Drew requests on 2026-10-27. Add further implementation sub-issues after scope approval and an authorized feasibility trial. Apple Intelligence blocks neither Rolling Round nor the extension. |
| Review defaults | Retain 60 recorded seconds across explicit segments. Pause gaps remain visible. Save/cancel resumes an eligible armed tab in a new segment. |
| Selection | Start with the marked failure and evidence-linked setup steps. One Save accepts the displayed selected steps. Reviewers may edit, remove, or adjust them. Export only the selected scope. |
| Setup outside excerpt | Expand the selection to include required setup. Include no hidden earlier steps, frames, or diagnostics. |
| Cleanup | Cancel clears the review draft and assistance caches. Retain only bounded tracking history. Stop, tab closure, browser exit, or site-permission revocation clears all unsaved data. Re-arm after closure or revocation. |
| Retention | Review has no inactivity timer. It stays bounded to frozen history. The October 28 standalone requirement supersedes a universal 15-minute Mac-disconnection expiry. Revise native-transfer retention during research. |
| Re-arming | Preserve old-site history for review until new arming replaces it. Start a fresh buffer for the newly armed site. Do not combine sites. |
| Missing evidence | Mark gaps and unavailable diagnostics. Distinguish no captured errors from an unavailable console. Save usable evidence without an extra prompt. |
| Save integrity | Publish one complete ended bundle. Repeated Save or reconnect delivery cannot duplicate it. Preserve a retryable draft after a save failure. Do not alter the ordinary active round. |
| Privacy defaults | Allowlist structured fields. Exclude typed values, secrets, cookies, storage, and hidden DOM content. Sanitize URLs and diagnostics. Mask sensitive form fields in media. Do not claim complete redaction. |
| Jev decision | Drew approves bounded ambiguous-element help outside Rolling Round on 2026-10-27. Use sanitized candidate details and selected still frames under existing consent. Keep a local fallback. |
| Remaining work | Resolve exact controls, byte/event limits, sanitization mechanisms, supported surfaces, and pilot thresholds in design. Validate them only after separate trial authorization. The October 27 review is complete. October 28 answers confirm quiet native saving, an authenticated invited-user Jev service, sponsor-funded limits, and Mac-first support. See the architecture and service specifications. |

Ask only material product questions that arise from new evidence. Settle routine choices without extra reviewer inputs.

## Deferred scope

No automatic code editing, browser control, hosted team board, generic session replay service, or direct issue publishing is approved. Minimum authentication for the approved standalone Jev service is in scope. A broader account product remains deferred. No claim of support for every website, every frame, original source code, or mobile browsers is justified by this spike.

## Backlog record

Umbrella: [#124](https://github.com/spurs-planks-smithers/Capso/issues/124). Rolling Round sub-issue: [#157](https://github.com/spurs-planks-smithers/Capso/issues/157). Optional Apple Intelligence follow-up: [#148](https://github.com/spurs-planks-smithers/Capso/issues/148). All stay in Later without due dates. Each carries enhancement, question, and one severity label, sev-polish.

Initial severity rationale: current screenshot feedback still works. The extension adds context. Reassess severity if an interview establishes a task that users cannot complete.

This file records discovery only. Keep it and the issue synchronized as Drew answers. Drew authorizes documentation commits and a docs-only PR on 2026-10-28. App builds, dependency installation, feature flag changes, implementation, and deployment remain outside this work.
