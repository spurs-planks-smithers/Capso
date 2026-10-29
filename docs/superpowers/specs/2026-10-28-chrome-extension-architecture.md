# Nextshot Chrome extension: architecture and specification plan

Current direction, 2026-10-29: use native editing when Nextshot is available. Keep standalone browser editing without the app. The [native-first decision](../../decisions/2026-10-29-browser-native-first.md) supersedes browser-first review and quiet launch only after Save. Native draft editing is not implemented by the current finished-report importer.

Execution remains authorized through the [implementation plan](../plans/2026-10-28-chrome-extension-implementation.md). Keep #124, #157, optional #148, and all follow-up issues in Later. Exclude v0.5.0. No public release is authorized. v1.0 or later is tentative.

## Private pilot order, October 29

Drew selects Chrome-only friend tests on Windows and Mac. The separate [friend pilot](../plans/2026-10-29-chrome-friend-pilot.md), #182, delivers ordinary standalone capture first. Its popup excludes native, recording, and model setup. Windows remains pilot validation rather than a general release claim. The full product retains the native-first direction below.

## Priority and scope

Drew's top priority is a lightweight, unobtrusive extension with low overhead and few inputs. Chrome use must feel consistent with Nextshot on the Mac. The extension must also complete its core workflow without the app. Use the native app by default when available. Basic capture, editing, save, and export also work without it.

The October 28 request supersedes the October 27 Mac-required scope. Mandatory reconnect-before-save and universal 15-minute Mac-disconnection expiry no longer apply to browser-owned capture or saved results. Any native-transfer expiry must be separate and cannot erase the browser result.

Core standalone scope includes area capture, annotations, notes, annotation-based element context, a local round, an agent-neutral prompt, and portable export. Rolling Round follows its own off-by-default flag and existing selected-history requirements. Drew selects lightweight diagnostics on October 28. Deeper debugger access is deferred. Standalone Jev through a separate authenticated service is confirmed. Start with invited pilot users. Nextshot funds a bounded allowance. Local suggestions continue at the limit.

Drew confirms a Mac-first release on 2026-10-28. Design for current desktop Chrome. Keep the browser core portable. Claim no Windows, Linux, Edge, or Safari support before later validation. Preserve Nextshot's macOS 15 floor for optional native integration.

Evidence: [external research record](../../research/2026-10-28-chrome-swift-integration.md), [Chrome discovery](../../plans/2026-10-27-chrome-extension-discovery.md), and [Rolling Round plan](../../plans/2026-10-27-rolling-round-discovery.md). Platform facts and proposed design choices are separate in that record.

## Proposed architecture

Use TypeScript compiled to packaged JavaScript, semantic HTML, and small CSS. Start with platform controls and system fonts. Avoid an application framework unless a measured need justifies it. Keep Swift in the Mac app and optional bridge. Do not require Swift-to-WebAssembly, Electron, a local server, a background login item, or a remote account for basic capture.

| Component | Owns | Lifetime |
|---|---|---|
| Extension coordinator | Commands, permission checks, state recovery, routing, and selected metadata | Event-driven Manifest V3 worker; sleep when idle |
| Page adapter | Area selection and bounded element lookup. Armed interaction/error collection where permitted | Inject for deliberate capture; attach recording listeners only while armed |
| Native review | Draft image/history, annotations, notes, selected issue, accepted steps, and publication | Open for deliberate native editing; reuse the existing native tools |
| Browser review | Standalone editing, notes, selected issue, accepted steps, and local save | Open when native editing cannot run; no permanent sidebar |
| Recorder/export worker | No-audio stream, bounded rolling media, masking, selected frames, encoding | Offscreen document only while a task or unsaved buffer needs it |
| Browser round store | Saved round metadata and assets, portable bundle generation | Extension-owned local storage; no page storage or cloud sync |
| Swift bridge | Host identity, capabilities, draft ownership, validated selected transfer, status, and publication receipt | Short operations where sufficient; proposed bounded connection only during active native review |
| Native app coordinator | Native draft editing, ordinary round publication, independent ended Rolling Round, eligible assistance | Start the paired installed app for deliberate editing. Reuse its existing instance when running. |
| Standalone Jev service | Invited-user authentication, bounded allowance, sanitized inference, and response validation | Run a bounded request during deliberate review. No tracking-time stream or hosted round archive. |

Native-first flow: freeze and mask the browser capture, then hand an editable draft to Nextshot. Use native annotations and notes. Publish once after completion and copy the native prompt. Do not open a browser annotation page during a successful native path. Standalone mode uses the browser editor and local store.

The current signed helper and authenticated Apple Events deliver completed reports. They do not implement editable drafts, reliable closed-app discovery, or native control of a browser-owned review. Preserve their verified security boundaries. Define the new capabilities, owner, status, cancel, and final-publication contracts through #178 and #179 before dependent coding.

A deliberate native edit may start the paired app before Save. This supersedes quiet launch only after browser Save. Never launch for installation, page load, idle, or presence polling. Disabled integration stays disabled. Preserve the draft after failure. Resolve uncertain transfer ownership before opening another editor. Keep the required privacy and site grants.

The app remains the only writer of its active round state. The helper must not create a second independent writer over `FeedbackRoundStore` or `.active.json`. Proposed ordinary-capture routing joins the native active round or starts the default round when none exists. Use stable source IDs for deduplication and preserve the app's capture numbering. Native Rolling Round import creates an ended round and preserves any ordinary active round. Browser-only capture has no native active-round dependency.

## Contracts and lifecycle

### Draft and publication ownership

Resolve the editor once per deliberate operation. Chrome owns frozen browser evidence, masks, permission checks, and the rolling buffer. Nextshot owns editing and saved rounds on a native path. Browser-only editing owns its local result. Avoid duplicate finished reports by default.

Use stable draft IDs, source digests, edit revisions, version negotiation, and explicit editor ownership. Distinguish staged, editing, saved, canceled, and failed states. A staged acknowledgement confirms no publication. Retry and status recovery must preserve one editor and one saved capture. The final edited digest is separate from the source digest.

Do not expire a saved result as temporary transfer cleanup. Do not loop indefinitely, launch repeatedly, or poll while idle. Retrieve uncertain status through a bounded active operation. Keep a usable standalone draft when native editing cannot run.

### Shared evidence contract

| Group | Proposed fields and rule |
|---|---|
| Identity/version | Protocol version, bundle schema version, stable round/capture IDs, source build, and intended Dev/release channel |
| Reviewer authority | Marks, note text, selected issue moment, chosen excerpt, and accepted steps. Keep separate from untrusted page content. |
| Capture geometry | Timestamp, page/frame identity, viewport, crop origin, scroll, zoom, pixel scale, and geometry mapping. Detect stale evidence. |
| Element evidence | Bounded selectors, role, safe attributes, nearby text, bounds, ancestry, and reliable source location when available. No invented source mapping. |
| Time evidence | Monotonic event offsets, capture timestamps, segment identifiers, pause gaps, and links from steps/diagnostics to selected media |
| Assets | Named relative assets, type, length, and digest. Reject traversal, unsafe names, unsupported types, and unexpected sizes. |
| Diagnostics | Sanitized permitted error text and request summaries. Include collection start/stop and unavailable coverage. No headers, bodies, secrets, or entered values. |
| Receipt | Stable import ID, accepted schema/channel, completion state, and bounded error category. Emit success only after a complete publication. |

Share one documented schema and example fixtures across browser and Swift. Map the native side through typed Codable values. Native-only rounds use schema 1. Browser imports use schema 2. Preserve backward reading and the older-app compatibility guard. Do not reuse the current native shape as an unchecked external command interface.

For native transfer, allow only named capabilities and operations. Validate the extension sender before forwarding and validate again in Swift. Permit no arbitrary shell command, source filename, destination path, endpoint, or app selection from page data. Use exact extension IDs and channel-specific host names. Registration and schema allowlists do not prove immunity from locally compromised software.

### Storage and cleanup

Keep unsaved rolling media in bounded memory owned by the active recorder/review context initially. Persist only small session-control metadata. Standalone saved rounds use extension-owned IndexedDB. Native saves use the native round store. Do not place images or logs in Chrome sync storage. Restrict storage visibility to trusted extension contexts.

Memory pressure or recorder loss can shorten available history. Record the gap and keep the remaining history usable. Do not silently promise a complete 60 seconds. If later measurements require disk-backed unsaved media, design restart/crash cleanup before adopting it. Browser shutdown callbacks cannot be assumed to run.

Retain the approved Stop, cancel, tab-close, browser-close, permission-loss, and cross-site re-arm rules. Mac absence is no longer a tracking pause reason. Review and tab-switch pauses still preserve history with explicit segment boundaries. A stopped stream may require a new capture gesture; verify automatic resumption before promising it.

### Permissions and unobtrusive operation

| Capability | Proposed access rule |
|---|---|
| Ordinary capture | `activeTab`, `scripting`, and extension storage. Request persistent access for the selected site once, as approved. |
| Embedded preview | Request needed frame origins deliberately. Fall back honestly when an inner element is unavailable. |
| Rolling/explicit recording | Request recording capability on deliberate arming. Use an offscreen owner and no audio. Preserve Chrome's required capture indicators. |
| Network summaries | Observe only during armed tracking and within permitted origins. Do not request headers, bodies, blocking access, or blanket origin access. |
| Native integration | Request `nativeMessaging` when native integration is enabled. Missing/denied access leaves core browser use intact. |
| Export/copy | Prefer user-initiated platform actions. Use downloads or clipboard permissions only where the validated flow requires them. Honor Chrome's download settings. |
| Deep debugging | Excluded from the first extension, confirmed by Drew on 2026-10-28. `debugger` cannot be an optional permission. Any later expansion needs a new scope decision. |

No native presence polling, permanent native port, idle recording, continuous Jev requests, always-open sidebar, or whole-page mutation observer belongs in the default flow. A temporary active-review connection remains a feasibility proposal and must tear down after review. One Save accepts the displayed selected steps. Generate titles and filenames automatically. Keep format/size optimization internal. Exact controls await visual design and later approval.

### Recording, excerpt, and assistance rules

Retain the 60 recorded seconds, issue-first review, one-second optional confident issue suggestion, and one-second useful local step result. Suppress late or weak issue guesses. Review never waits for Jev. Local suggestions stay usable in every mode.

Prefer browser-native media recording and encoding. A larger codec runtime needs measured justification. Frame boundaries and container chunks do not establish exact clip boundaries. Prove that the selected interval excludes earlier/later media. Feature-detect codecs and document browser/native compatibility. Keep GIF when efficient, compact video when useful, and still-frame fallback when needed.

The complete package has a soft 5,000,000-byte target. Optimize automatically. If animation-free output remains larger, save the smallest practical package normally. Keep accepted steps and matching diagnostics. No size prompts, forced shorter excerpt, or manual optimization controls.

Jev may receive only approved sanitized event/element details, relevant diagnostics where allowed, and selected still frames. Never send GIF/video. Keep existing consent, dev-only feature review, and native endpoint restrictions. The browser service has a separately scoped transport and authentication boundary. Service planning does not authorize new native endpoints or release defaults. Apple Intelligence #148 stays optional and does not block core browser use.

## Product decisions

Asked live through structured questions on 2026-10-28. These are material workflow and service choices. Routine design choices above do not need another interview.

| Topic | Decision | Status |
|---|---|---|
| Native capture shortcut | Keep the normal Nextshot shortcut. Add permitted browser details automatically when Chrome is frontmost on approved sites. Preserve native capture when details are unavailable. | Confirmed by Drew on 2026-10-29; trigger feasibility remains #178 |
| Diagnostic breadth | Use lightweight observable errors and permitted request summaries. Label gaps. Exclude debugger permission from the first extension. | Confirmed by Drew on 2026-10-28 |
| Installed app is closed | Start the paired app for deliberate native editing before Save. | October 29 native-first direction supersedes the October 28 Save-only launch decision |
| Standalone Jev | Include a separate authenticated service. Preserve local suggestions when it is unavailable or capped. | Confirmed by Drew on 2026-10-28 |
| First supported platform | Mac first. Keep the browser core portable for later expansion. | Confirmed by Drew on 2026-10-28 |
| Service audience | Invited pilot users first. Public access is a later product decision. | Confirmed by Drew on 2026-10-28 |
| Service funding | Nextshot pays within usage and spending limits. Local suggestions continue at the limit. | Confirmed by Drew on 2026-10-28 |

## Standalone service boundary

The [standalone Jev specification](2026-10-28-standalone-jev-service.md) records authentication, payload, consent, quota, cost, retention, and failure rules. It adds no required account to capture or local save. The invited user signs in only to enable remote assistance. Do not turn each request into a login or usage-confirmation step.

Use local suggestions immediately. Send one bounded request through the service only when the selected assistance and content consent allow it. The service holds upstream credentials and enforces access and limits. Never ship an upstream key in the extension. Late answers cannot overwrite reviewer edits.

Drew authorizes a hard $25 monthly pilot ceiling on October 28. The invited service is deployed and verified. Processing remains paused after bounded synthetic acceptance. This native-first review enables no paid calls, public enrollment, new endpoint, or release default. See the execution record for current operational evidence.

## Specifications and future evidence

The original specification areas below remain useful. Current native-first engineering follows #178 through #181, with design and simplification in #177. Final native-first smoke remains #172.

| Order | Specification | Required exit evidence |
|---|---|---|
| 1 | Browser capture and review | End-to-end native-independent flow, mark-to-element contract, action count, accessibility, and honest unsupported cases |
| 2 | Evidence and local round format | Versioning, browser/native ownership, selected assets, prompt/zip parity, privacy boundaries, and complete-save semantics |
| 3 | Optional native integration | Setup in either install order, signed helper registration, app relocation/update, channel pairing, native-round protection, and fallback |
| 4 | Recording and Rolling Round | Media lifecycle, exact selection, pause gaps, browser indicators, bounded memory/events, useful local steps, and cleanup |
| 5 | Standalone Jev and native assistance | Invited-user authentication, content consent, sponsor-funded allowance, global cost controls, retention, failure fallback, native release limits, and optional #148 |
| 6 | Performance and pilot | Baseline comparisons for idle, capture, armed, paused, review, and export. Set measured budgets before implementation approval. |

The execution record verifies embedded previews, exact selected export, and finished native delivery. Native capture triggering, temporary native review transport, draft editing, and native media playback remain unproven. Verify them before native-first acceptance.

Do not claim zero overhead, universal source mapping, universal console coverage, invisible recording, or automatic first-run native pairing. Measure startup latency, wakeups, memory, processor/energy use, bundle bytes, and export time. Do not invent targets from documentation.

Both PR #161 and implementation PR #173 remain draft and unmerged. This review changes planning documents and tracking only. Keep native-first flags off pending Dev acceptance. Do not promote a release milestone or publicly release this work.
