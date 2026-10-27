# Secure feedback intake implementation

Approved by Drew on 2026-10-26 in this chat. The public service stays disabled until its launch checks pass.

## Product decisions

- Website intake accepts bugs, feature requests, questions, and other inquiries.
- Optional email permits anonymous submissions. No automatic acknowledgment goes to an unverified address.
- Native submission stays in the app. It uses no browser challenge or account.
- Native submission sends a reduced package with annotated JPEGs, notes, and minimal version information.
- Native submission has one optional note line, optional email, a content disclosure, Submit, and Cancel. No full capture review is required.
- Native support packages omit clean images, OCR fields, window-title fields, source filenames, generated prompts, and Jev files.
- Website attachments accept supported Nextshot exports and PNG/JPEG images only.
- Incoming mail uses hi@nextshot.dev. Screened plain text goes to drewschulz1@gmail.com. Replies use personal Gmail.
- Suspicious content stays held. No automatic redaction clears a submission.
- AI can prepare private issue drafts. It receives no tools, repository access, or publishing credential.
- Held material expires 30 days after receipt. Screened material expires 90 days after receipt. Gmail retention is separate.
- The operating target is about $50 per month. Pause expensive processing near $40 estimated spend.

## Trust boundaries

1. Public HTTP and email input enters private quarantine.
2. A scanner checks structure, malware, decoded images, text, and prompt injection.
3. Tool-free contextual checks inspect text and images.
4. The service can release only rebuilt derivatives after all required checks pass.
5. Owner review requires Cloudflare Access and application-level token validation.
6. Issue drafts remain untrusted data. A passed scan grants no authority to instructions inside a submission.

No original attachment has a public or owner-download route. Scanner failures, stale definitions, incomplete coverage, and model failures never become a pass.

## Shared interfaces

The native transport calls only https://feedback.nextshot.dev. It uses an ephemeral URL session, refuses redirects, and retains normal TLS certificate checks.

| Operation | Route | Contract |
|---|---|---|
| Reserve | POST /v1/reservations | source, category, message, optional contactEmail, idempotencyKey, file name/bytes/SHA-256/contentType; web also sends turnstileToken |
| Upload | PUT /v1/submissions/:id/files/:fileId | Bearer reservation token and counted raw bytes |
| Complete | POST /v1/submissions/:id/complete | Bearer token; idempotent queue admission |
| Status | GET /v1/submissions/:id | Bearer token; receipt and state only, never submission content |

Reservations expire after 10 minutes. Object identifiers come from the server. Native client headers establish no identity or privilege.

The reduced archive has one support.json file and generic capture-N.jpg images. Its schemaVersion is 1. Its app object holds version, build, channel, and osVersion. Each capture holds index, imageFile, width, height, note, and items. Each item holds id and instruction. Optional submission note and contact information remain separate from the original round.

The scanner job holds submission metadata and bounded file bytes. Its typed result has version, status, reasonCodes, canonical text, inspectionText, rebuilt images, and scan metadata. Held and rejected results contain no content excerpts or images. Required scan metadata records engine, definition age, classifier revision, and policy version.

## Limits

| Resource | Limit |
|---|---:|
| Uploaded file bytes | 10,000,000 |
| Expanded archive bytes | 50,000,000 |
| Archive entries | 100 |
| Captures | 20 |
| Individual image area | 20,000,000 pixels |
| Total decoded image area | 80,000,000 pixels |
| Extracted text | 100,000 bytes |
| Scanner attempt | 120 seconds |
| Concurrent file scans | 1 |
| Submissions per IP-derived identifier | 5 per hour, 20 per day |

Reject encrypted or nested archives, executables, unsupported documents, traversal paths, symbolic links, duplicate paths, invalid schemas, and malformed images. Count bytes and pixels during processing. Do not trust declared sizes.

Email has separate channel-wide quotas because the delivery IP does not identify its sender. Sender-based quotas are weak signals only. Global byte, job, and cost limits apply across channels.

## Implementation tasks

1. Native support package, local checks, compact submission panel, fixed-host transport, and feature flag.
2. Worker reservations, immutable uploads, completion, state handling, quota reservations, storage, and owner access.
3. Isolated ClamAV, image normalization, OCR, private-content rules, Prompt Guard, and signature maintenance.
4. Context screening, private issue drafts, reconstructed notifications, email ingestion, and expiration.
5. Integrated verification, signed Dev build, protected staging, and launch readiness.

Parallel implementers use separate managed worktrees. The root checkout integrates reviewed commits. Ordinary exports remain unchanged.

## Required checks

- Valid messages, pasted prompts, screenshots, ordinary exports, and reduced packages.
- Synthetic malware markers, archive bombs, traversal, encryption, type mismatches, malformed images, and decoded limits.
- Injection in notes, images, generated prompts, mail headers, and model output.
- Synthetic credentials and private records, OCR uncertainty, and uncertain model results.
- Stale signatures, unavailable engines, duplicate queue messages, partial uploads, exhausted quotas, and notification failures.
- Unauthorized owner access, expired tokens, cross-site mutations, and release-bucket isolation.
- Deletion across originals, derivatives, content records, and expired work.
- Affected Swift tests, Release Jev tests, app build, and signed Dev behavior.

## Launch dependencies

Verified on 2026-10-26: the current Nextshot Cloudflare credential cannot administer Containers or Email Routing. The account's billing subscription is not visible with this credential. No Hugging Face credential exists in the secret index or the inspected Keychain services. Prompt Guard 2 requires an approved model download and its license notice.

These dependencies are launch gates. They do not justify weakening scanner checks or enabling public intake early.

## Sources

- [OWASP file uploads](https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html)
- [OWASP prompt injection](https://cheatsheetseries.owasp.org/cheatsheets/LLM_Prompt_Injection_Prevention_Cheat_Sheet.html)
- [Cloudflare upload scanner limits](https://developers.cloudflare.com/waf/detections/malicious-uploads/)
- [Cloudflare Containers pricing](https://developers.cloudflare.com/containers/platform/pricing/)
- [Container outbound controls](https://developers.cloudflare.com/containers/configuration/outbound-traffic/)
- [Cloudflare email authentication](https://developers.cloudflare.com/email-service/reference/postmaster/)
- [Prompt Guard 2](https://huggingface.co/meta-llama/Llama-Prompt-Guard-2-22M)
