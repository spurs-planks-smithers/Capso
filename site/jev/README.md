# Invited Jev pilot service

## Status

Isolated Worker source for C6, issue #170. Processing starts disabled. No deployment, provider call, account, or secret is created by this change. Existing feedback transport and native Jev policy stay separate.

## Provisioning

Use a new Worker hostname, D1 database, Access application audience, and provider credential. Fill the empty external identifiers in `wrangler.jsonc`. Protect only `/auth/authorize` with Cloudflare Access. The JSON token and inference routes use scoped bearer credentials. They need no Access cookies. Keep public enrollment disabled.

Apply `schema.sql` to the new database. Invite a user by inserting a unique internal ID, SHA-256 of `https://<Access team domain>\n<verified Access sub>`, enabled=1, and an explicit monthly allowance in integer microdollars. There is no public invitation route. Set enabled=0 to revoke all future access. Do not delete accounting records.

Provision `TYPESAFE_API_KEY` as a Worker secret through the approved secret workflow. Never put it in configuration, browser assets, or a source file. This package does not read Keychain.

## Protocol

The client ID is `nextshot-chrome-dev`. The only redirect is `https://ghmidcmcjigfckaiopacgpfaffofgjel.chromiumapp.org/jev`. Authorization requests use response_type=code, scope=jev:refine, S256 code_challenge, and random base64url state of 32 to 128 characters. The client must verify its exact state and returned `iss` before exchanging the code. Access identity JWTs require the configured issuer, separate audience, RS256, subject, issue time, and expiry. The service allowlist is independent of Access admission.

POST JSON to `/auth/token` with grant_type=authorization_code, client_id, redirect_uri, code, and code_verifier. Codes expire after 120 seconds and consume atomically. Access credentials expire after one hour. The reply includes access_token, refresh_token, issuer, audience, scope, and expires_in. Validate issuer and audience in the client. Tokens are opaque, stored by hash, and checked against enabled identity and session revocation on every request.

For silent review-time refresh, POST grant_type=refresh_token, client_id, and refresh_token to `/auth/token`. A refresh rotates once. Its family expires 30 days after sign-in, without extension. A replay revokes that entire family, including concurrent descendants. Serialize refresh calls in the client. POST `/auth/revoke` with the bearer token revokes its whole family. No automatic interactive reconnect belongs in capture.

GET `/v1/availability` reports current eligibility and user remaining requests. POST `/v1/refine` accepts version=1, purpose=steps or elements, requestID, selectionVersion, consent={pageData:true,reviewerText:boolean}, optional reviewerNote, timeline, diagnostics, and candidates. Reviewer text requires its own consent. Arrays are required. Timeline has at most 32 entries with id, kind, label, timeMs (0 to 60000). Diagnostics has at most 8 entries with id, kind, summary. Candidates has at most 16 entries with id, role, label. Text is bounded to 512 characters; reviewerNote is bounded to 1024. IDs use 1 to 64 ASCII letters, numbers, underscores, or hyphens. Unknown fields, images, media, URLs, email addresses, and common credential patterns are rejected. Client sanitization remains required because a text filter cannot recognize every sensitive value.

The response repeats requestID, selectionVersion, and purpose. It returns only supplied IDs and confidence values. It cannot write text, steps, locators, or reviewer edits. The client rejects stale selections and applies suggestions only through reviewer acceptance. Every unavailable result includes fallback=local. A repeated logical request returns already_attempted. Reusing its ID with different content or identity returns request_conflict. No result content is stored for replay.

## Paid admission

The hard global limit is 25000000 microdollars ($25) per UTC calendar admission month. Each user has a separate lower allowance. SQLite BEFORE INSERT triggers enforce both totals atomically and apply a six-request-per-minute identity limit. Every admitted request reserves 2688 microdollars permanently. No refund occurs after success, error, timeout, or uncertain execution. Request IDs remain globally unique across months. Uncertain previous-month requests retain their original reservation. New work uses the new admission month. Accounting rows cannot be deleted or have reservation metadata changed. They contain IDs, content digests, status, timestamps, and cost only.

[TypeSafe models](https://docs.typesafe.ai/models) reports $0.042 per million input tokens, free output, and 64k per-request context. [System One](https://docs.typesafe.ai/api/system-one) defines usage.input_tokens as billable input. The native JevKit adapter confirms POST `/v1/systemone`, state, typed questions, and model checks. This adapter pins `jev-1.14.0`, uses Noul questions, sends no experimental headers, refuses redirects, allows 800 milliseconds, and caps the response at 32768 bytes. It makes one attempt.

The phrase 64k does not independently prove an exact 64000 billable-token ceiling or exclude separate charges. `BILLING_BOUND_VERIFIED` therefore starts false and blocks paid admission, even if PROCESSING_ENABLED is true. Before activation, obtain provider confirmation that a request without experimental headers costs no more than 2688 microdollars, including all billable input and any other fees. Otherwise revise the reserve and schema together using a proved upper bound. Missing or changed model/pricing settings also block paid execution.

## Verification and limits

Local checks cover Worker packaging, D1 session revocation, PKCE mismatch, exact redirect rejection, one-time code exchange, refresh rotation/replay, payload exclusions, disabled fallback, concurrent user quota, immutable uncertain reservations, month reset, fixed provider endpoint, model mismatch, and oversized response fallback. Separate SQLite concurrency checks put the global total at 24998400 microdollars and reject 30 concurrent additions.

Live Access sign-in, actual provider behavior, provider retention terms, and extension integration require external setup and review. No mock proves them. Provider zero retention is not assumed. Do not activate until retention disclosure, exact billing bound, separate Access configuration, allowlist, user allowance, and Chrome sign-in/revocation smoke pass. Keep the tracked work in Later and outside v0.5.0.

Refresh/code metadata can be pruned after expiry. Never prune request accounting rows without a replacement permanent idempotency/accounting store. This first pilot has no content archive, durable response cache, public enrollment, hosted library, or background retry queue.
