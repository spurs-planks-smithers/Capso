# Standalone Jev service: product and boundary specification

October 29 acceptance update: invited PIN sign-in, live cap fallback, credential revocation, and bounded provider review pass. Issues #170 and #171 are closed. Processing is paused. The approved $25 monthly ceiling remains enforced. The [execution record](../../sessions/2026-10-28-chrome-extension-execution.md) records actual results and remaining user smoke. Earlier planning and deployment snapshots below remain historical.

Execution update, October 28, 2026: Drew subsequently authorizes implementation and a $25 monthly hard ceiling for paid Jev pilot calls. The [implementation plan](../plans/2026-10-28-chrome-extension-implementation.md) supersedes the planning-only restrictions below. The historical product requirements remain relevant. Current implementation and deployment limits live in [the service guide](../../../site/jev/README.md). The owner-only service is deployed with paid processing disabled. Guest authentication and live paid acceptance remain open. Keep the work in Later and outside v0.5.0.

Date: 2026-10-28. Status: planning only. Part of [Chrome extension #124](https://github.com/spurs-planks-smithers/Capso/issues/124). Rolling Round is [#157](https://github.com/spurs-planks-smithers/Capso/issues/157). Apple Intelligence [#148](https://github.com/spurs-planks-smithers/Capso/issues/148) remains optional. Keep all work in Later. Exclude v0.5.0. No implementation, service deployment, paid request, or purchase is authorized.

## Confirmed scope

Drew confirms these decisions through structured questions on October 28, 2026. The service provides Jev without the Mac app. It serves invited pilot users first. Nextshot funds usage within a bounded allowance and spending controls. Reaching a limit leaves local suggestions available. The first supported browser platform is Chrome on macOS. Keep the core portable for later expansion.

The service improves suggestions during deliberate review. It is separate from browser capture, recording, local storage, and native import. Basic capture and save require no service account. Network failure, expired authentication, or an exhausted allowance must not block those operations.

The [architecture specification](2026-10-28-chrome-extension-architecture.md) owns quiet app launch and browser/native delivery. On Save, preserve the browser result first. When the native bridge is available, start installed Nextshot quietly and import automatically. That requirement does not make the service dependent on the app.

This is a narrow inference service. A hosted round library, team board, public enrollment, subscription billing, and cross-device synchronization are outside this first pilot. Apple Intelligence #148 is an optional later enhancement. It is not a service dependency.

## Service contract

Use one small service boundary for authentication, admission checks, quota accounting, inference, and validated replies. Keep upstream adaptation isolated. Add no durable media archive, general job platform, vector database, or always-running client connection without evidence of need.

| Operation | Allowed input | Required result |
|---|---|---|
| Establish access | Invited user identity and a valid authorization flow | Scoped, revocable service access. Rejected or unavailable access leaves local work usable. |
| Recommend selected steps | Sanitized selected action timeline, relevant permitted diagnostics, optional selected still frames, selection version, and request ID | Evidence-linked step candidates with bounded structured fields |
| Resolve an ambiguous element | Sanitized candidate-element details and optional selected still frame, with candidate IDs | Rank or identify captured candidates. Never invent an element or a source location. |
| Report availability | Access status and bounded allowance information for the current user | Machine-readable eligibility. Do not expose provider keys or require a prompt for each request. |

The service accepts only known operations and a versioned request schema. It validates field types, counts, lengths, image types/dimensions, and total input size. A page cannot supply a fetch URL, model endpoint, file destination, or arbitrary instruction operation. Reject unknown operations. Keep reviewer notes separate from untrusted page content.

The client prepares a useful local result first. Remote refinement is asynchronous. Optional issue recommendations still obey the one-second deadline and confidence rule. A late or unsupported guess stays silent. Requests carry the selection version. Changing the selection or canceling the draft invalidates the old response.

Return candidate IDs and evidence offsets that refer to supplied material. Validate the response in the service and client. Generated wording cannot override a reviewer edit, accepted step, selected issue, or chosen excerpt. No code execution or automatic fix belongs in this contract.

## Authentication and consent

Use a standard external-browser authorization flow suitable for a public client. Chrome supplies [Identity APIs](https://developer.chrome.com/docs/extensions/reference/api/identity). The [OAuth security best practice](https://www.rfc-editor.org/rfc/rfc9700) informs the design. Validate the selected identity provider and redirect flow before fixing the mechanism. Login method and token format are technical design choices.

Proposed direction: authorization code with Proof Key for Code Exchange (PKCE). PKCE binds the authorization result to the initiating client. Validate state, exact redirects, issuer, audience, scopes, and expiration. A client identifier is public. Never bundle a shared upstream or service secret in the extension.

Invite-only admission is enforced by the service. An extension flag or a hidden page does not establish eligibility. Revocation stops future remote access. Preserve existing local and saved work. Upstream provider keys and confidential service secrets stay outside the extension. The extension may hold scoped, revocable user access tokens through the approved identity flow. Runtime credential provisioning must follow the approved deployment and secret workflow. No credential is created, read, or moved during this planning work.

Ask the user to enable remote assistance and sign in once when needed. Explain the approved data categories at that point. Do not open a login page during capture, on every request, or after a routine background refresh failure. Offer a nonblocking reconnect action during review when needed. Keep local results available.

Authentication does not grant content consent. Apply separate content-kind checks before sending reviewer text, captured screen/page data, or images. Preserve the already approved sanitized timeline, relevant diagnostics, candidate details, and selected still-frame boundaries. No GIF, video, audio, full page snapshot, network header, or network body enters the service.

The approved browser service does not change the Mac's current fixed endpoints, dev-only Jev gates, or release-review policy. Plan a separate off-by-default browser Jev flag. A flag, invite, authenticated session, and content consent serve different purposes. Pilot activation needs the required review. A later native client for this service needs its own explicit transport and policy review. Do not reuse SupportKit's submission path or its consent for inference.

## Cost and availability

Nextshot pays for the invited pilot. The service enforces a per-user allowance and a global spending ceiling. The exact amounts belong in a later pilot-activation proposal. This document authorizes no spend and invents no quota numbers.

| Control | Required behavior |
|---|---|
| User allowance | Admit only requests that fit the configured user allowance. At the limit, continue with local suggestions. |
| Global spending ceiling | Stop new paid admission before the configured budget is exceeded. Reserve bounded potential cost before an upstream call. |
| Concurrent requests | Check and reserve allowance atomically. Parallel requests cannot each assume the same remaining budget. |
| Input/output bounds | Cap frames, image dimensions, text length, output length, and request time before model execution. |
| Repeated delivery | Use a stable logical request ID. Repeating the same operation does not intentionally create another billable job. |
| Retry uncertainty | Do not repeat a timed-out paid request blindly. Use upstream request identity or stop and keep local suggestions when its result is unknown. |
| Abuse controls | Rate-limit by authenticated identity and bounded installation/session signals. Do not rely on a public extension ID alone. |
| Operations | Keep a service kill switch, provider failure handling, and cost/latency counters without captured content. |

Choose provider routing, request limits, and cost reservation during design using actual terms and prices. A cap must include concurrent work and uncertain in-flight requests. A report that exceeds its size target does not authorize a larger inference request.

An exhausted allowance or service failure produces no paywall, checkout, forced retry, or save interruption. Continue with the local result. An optional status in review may explain why refinement is unavailable. Detailed spending controls remain internal. Do not prompt for provider choices, token limits, or package optimization.

## Data lifetime and failures

Keep the browser as the saved report's owner. Send only selected, sanitized inference material. Process content transiently. Persist minimal operational metadata, such as request ID, eligible identity reference, cost accounting, latency, status, and deletion deadline. Do not log notes, screenshots, page text, raw URLs, tokens, or diagnostics.

Prefer synchronous bounded inference with no server-side content archive. If an upstream provider retains request content, disclose and validate that behavior before the pilot. Do not claim zero retention until both the service and provider behavior support it. Training and evaluation reuse of captured content are not approved.

Client cancellation prevents applying the answer and stops further work where possible. It cannot recall data already sent or undo completed upstream processing. Delete transient request material under the documented lifetime. A late result cannot recreate an expired, stopped, or canceled draft.

| Failure | User-facing behavior |
|---|---|
| Offline, timeout, provider failure, or service shutdown | Keep local suggestions and normal capture/save. Require no retry. |
| Missing, expired, or revoked access | Keep local work. Offer service reconnection only during deliberate review. |
| User or global allowance exhausted | Continue with local suggestions. Apply no paid overage automatically. |
| Invalid or unsupported response | Discard it. Preserve the reviewer state and local result. |
| Changed selection or closed draft | Reject the stale answer. Do not alter the new selection or recreate discarded data. |
| Native app unavailable | Keep standalone service access and browser save independent. |

## Future verification and approval

| Specification evidence | Required before pilot activation |
|---|---|
| Authentication | Invited access, exact redirects, session refresh, revocation, and failure fallback |
| Consent | Field-level request examples for every permitted data kind. Proof that excluded media and sensitive fields cannot enter requests. |
| Quality | Captured-evidence links, local baseline comparison, stale-response rejection, and no silent replacement of reviewer edits |
| Cost | Actual provider pricing and bounded unit-cost estimates. Explicit per-user allowance and global ceiling proposed for approval. |
| Retention | Service and provider lifetimes, content-log exclusions, cancellation limits, and deletion behavior |
| Availability | Offline, capped, invalid response, timeout, and uncertain paid-call cases preserve local capture and save |

These are future evidence requirements. This task runs no authentication flow, request, service deployment, provider evaluation, or performance test. It creates no account, key, billing plan, database, or infrastructure. The exact spend proposal and activation approval remain a later step.

No further product question is needed for this specification pass. Keep the docs-only PR open. Do not merge or start building without a separate request.
