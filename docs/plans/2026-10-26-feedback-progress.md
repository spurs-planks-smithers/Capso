# Feedback implementation progress

Plan: [[2026-10-26-secure-feedback-intake]]

## Workspace

- Root starts at 373ea80 on feature/secure-feedback-intake. The Guides branch stays preserved.
- Native, service, and scanner implementers use separate managed worktrees.
- Shared API routes and scanner contracts are implemented and reviewed.

## Implementation

| Area | Current result |
| --- | --- |
| Native app | SupportKit, reduced archives, local checks, compact native panel, cancellation, and duplicate protection implemented. supportSubmission stays off. |
| Service | Website, bounded intake, quarantine, queue, owner review, false-positive approval, notifications, retention, and private drafts implemented. All six launch switches stay false. |
| Scanner | Strict archive schemas, ClamAV, image rebuilding, OCR, privacy rules, pinned Prompt Guard loader, hard timeouts, and restricted network path implemented. All seven approved model artifacts are hash-verified. Real classifier, OCR, and malware checks pass. |
| Recovery | Immutable upload attempts, leased scan/notification claims, and generation-bound review approvals implemented. |
| Integration | Root includes commits through dae8ddf. Policy exception, runbook, signature workflow, and homepage link are prepared locally. |
| Public launch | Disabled. No homepage deploy, native flag activation, or mail-routing activation. |

## Verified local behavior

| Check | Evidence |
| --- | --- |
| Service boundaries | 96 tests pass, including HTTPS, bounded model contexts, fresh scanner VMs, restore-safe retention, and approval races. Evidence: build/feedback-checks/service-tests-current.log. |
| Existing release site | 22 tests pass. /private/tmp/nextshot-site-tests-current.log |
| SupportKit | 6 tests pass. /private/tmp/nextshot-support-tests-current.log |
| FeedbackKit | 335 tests pass in native worktree verification. |
| JevKit Release | 369 tests pass in native worktree verification. |
| App tests | 247 tests pass. /private/tmp/nextshot-feedback-app-tests.log |
| Signed Dev app | Release build succeeds with Apple Development signature, no install. /private/tmp/nextshot-feedback-signed-build-final.log |
| Native UI | Real synthetic support panel rendered with 20 captures. No transport call or round data used. |
| Native transport | Real SupportTransport refuses the protected owner's 302 redirect with a synthetic package. No submission is created. Evidence: build/feedback-checks/native-transport-protected.json. |
| Scanner | 62 tests pass inside the local Linux image without network, with read-only root and 6 GiB memory. Cloudflare retains root capabilities inside its VM. |
| Dependency audit | Actual image inventory: 38 distributions, zero known vulnerabilities, zero skips or suppressions. /private/tmp/nextshot-feedback-python-audit-image-patched.json |
| Actual scan engines | Real clean/injection classifier, full bounded text, signed ClamAV clean/EICAR, OCR credentials, and local network denial pass. build/feedback-checks/approved-engines-final.log |
| Largest standard export | Real full scans pass: standard 20 captures in 45.697 seconds; reduced 20 in 32.563 seconds. One CPU, no network, all engines. Neutral synthetic images do not prove worst-case content latency. build/feedback-checks/approved-full-scanner.json |
| Signature task | Five tests pass with stdin closed. Only final mirror delivery is intercepted. The workflow requires main and a dedicated environment. Its branch restriction and credential remain unconfigured in GitHub. |
| Worker build | Wrangler bundle and Docker dry-run pass. /private/tmp/nextshot-feedback-root-bundle.log |

## Cloudflare setup

- User stores the seven-day setup token in Keychain as CLOUDFLARE_API_TOKEN_NEXTSHOT_FEEDBACK. Expiry: November 2, 2026.
- Three private R2 buckets exist: nextshot-feedback-raw, nextshot-feedback-rebuilt, and nextshot-feedback-signatures. Public access and custom domains are absent.
- D1 nextshot-feedback exists with metadata-only schema and eight tables. ID: 08e03222-27df-4ac6-947a-3e0586f2c7a0.
- Dedicated scan and dead-letter queues exist.
- Managed Turnstile widget is restricted to feedback.nextshot.dev. Its secret and the generated intake secret live in Keychain.
- User activates Workers Paid. Containers API access now passes.
- Enabled account usage alerts exist at $25, $40, and $50. They exclude recurring plan fees and impose no cap. The prior $10 alert stays enabled.
- Actual Llama 3.3 text and Llama 4 Scout image helpers pass six checks across nine hosted calls. Clean inputs pass; synthetic private records and injection hold. Draft schema and severity pass. Usage value is about $0.001761 before free allowance. Evidence: build/feedback-checks/models-helper-probes-scout-final.json.
- Gmail destination ownership is verified. Email Sending authentication is enabled with content previews disabled. Cloudflare provisions bounce MX, SPF, and DKIM records. The stricter existing DMARC policy and apex null MX stay unchanged.
- User activates Access Free. Review protection allows only drewschulz1@gmail.com, with one-hour sessions and no bypass policy. Whole-host staging protection and real owner sign-in pass. The application rejects forged tokens in local boundary checks.
- Signed malware definitions are published and hash-verified. The separate bucket-only credential passes a real refresh with stdin closed. Raw, rebuilt, and release bucket probes each return 403. Recurring GitHub refresh remains disabled.
- Item 1.1, October 26, 2026: Drew's capture shows accepted Llama 4 access. The live Prompt Guard page confirms granted access. Drew downloads the weights after Chrome blocks automation. All seven pinned artifacts pass exact size and upstream hash checks. The private scanner image builds and runs with the approved weights.
- Source resource report: build/feedback-checks/cloudflare-resources.json. Current preflight: build/feedback-checks/cloudflare-preflight-current.json.

## Required before launch

1. Complete the website submission and owner-review flow. Actual Cloudflare scanner isolation and engine checks now pass.
2. Confirm Gmail delivery, uploaded website exports, owner false-positive approval, private downloads, and remaining recovery checks. Actual stored-copy expiry passes.
3. Configure recurring trusted signature refresh after code review and GitHub publication approval.
4. Configure exact-address inbound mail routing after the live scanner passes. Keep the catchall disabled.
5. Review the signed running Dev app and public form before enabling their launch switches.
6. Resolve the unpublished Guides base before preparing feedback publication. Preserve the already live Guides site.

## Live staging

- The dedicated Worker and private scanner image deploy successfully using durable-object scheduling.
- The scanner uses the native Durable Object Container API. Cloudflare documents the SDK helper as unsupported for durable-object scheduling. Source controls require the fixed singleton, pinned digest, standard-2, denied internet access, bounded readiness, and 150-second inactivity shutdown.
- All six switches remain false in source. Protected staging enables web admission, processing, contextual checks, and notifications behind whole-host owner Access. Native and inbound email admission remain disabled. Native supportSubmission remains off.
- Disabled health/config checks and a rejected reservation pass. Review routes and forged-token attempts encounter Access.
- HSTS and insecure request guards deploy after the initial staging check finds HSTS absent.
- Drew signs into the actual review page on October 26, 2026. The owner list shows no submissions.
- Evidence: build/feedback-checks/staging-smoke-disabled.json and protected-staging-readiness.json.
- Actual cloud isolation passes: direct TCP and HTTPS are blocked, the private signature hash matches, and API/mail credentials are absent. Evidence: build/feedback-checks/private-isolation-report.json.
- Actual cloud engines pass: clean text passes, EICAR holds as malware_detected, and the real reduced export passes with two rebuilt images. Runs take 62.940, 60.106, and 82.661 seconds. Evidence: build/feedback-checks/actual-cloud-engines-scheduled.json.
- The temporary engine Cron is removed. The scanner stops with exit code 0. Each scan destroys the prior VM and destroys its own VM before clearance. Teardown failure withholds clearance.
- Cloudflare uses a 64-character hostname. Python's default HTTP server cannot resolve it. The server now binds directly without a hostname lookup. A local 64-character-hostname reproduction and the actual cloud engine checks confirm the fix.
- Protected web staging deploys with exact owner Access verified before and after deployment. Turnstile returns error 300030 after automated reloads. Drew reloads manually and submits receipt 1ae11f57. It completes screening and its notification send. No verification bypass is added.
- Two fixed synthetic MIME fixtures use the actual inbound parser and production queue. The clean fixture includes an inline synthetic JPEG. It completes screening, rebuilt-image storage, private draft preparation, and notification sending. An unsupported inline PDF stays held. Its content and files remain inaccessible in owner review.
- Actual expiry removes two originals, two payload generations, one rebuilt JPEG, one marker, and every related SQL row for the clean fixture. The held fixture is unchanged. Evidence: build/feedback-checks/private-operations-expiry-report.json.
- Drew authorizes inspection of the Nextshot test messages only. All three earlier notifications are verified in his Gmail Inbox. Screened text and protected review links are present. The held notice contains a count and reason without excerpts. Gmail shows nextshot.dev signing and TLS. The connector belongs to another account, so verification uses Drew's existing browser account. Evidence: build/feedback-checks/gmail-delivery-verified.json.
- Website ZIP receipt 0420d39f is received and held after full screening. Findings include payment details, private records, and an uncertain classification. Current policy correctly prevents approval and inspection. The fixture remains quarantined. A separate fixed fake-credential fixture tests the permitted false-positive path.
- Owner review now names uncertain classification, prohibited material, unsupported email attachments, incomplete screening, stale definitions, and budget exhaustion. An existing test first reproduces the generic-label failure. All 96 service tests then pass. The hold copy describes screening clearance without implying that processing is still running.
- Owner review renders the screened text, rebuilt-image link, and private issue draft. Chrome blocks the automated file download with ERR_BLOCKED_BY_CLIENT. Unauthenticated requests are denied. Manual download verification remains open.
- Real Swift exports pass structural and hard engine checks. The reduced package passes. The standard export is held because its generated date-based folder name passes a payment checksum. This synthetic false positive remains held for the owner approval test. Evidence: build/feedback-checks/actual-exports-scan.json.
- Hosted long-text screening passes across four actual model calls. Every request is bounded, and injection in the final chunk holds. A repetitive text fixture also holds as uncertain. Evidence: build/feedback-checks/context-chunks-live.json and context-chunks-repetition-held.json.
- No homepage update or inbound mail route is active. Public intake and the native app flag remain closed.

## Rulings and limits

- Engine substitutes never count as production scan evidence. Real local and Cloudflare engine checks pass. Website text and ZIP receipt, actual email parsing, review rendering, draft generation, Gmail delivery, and expiry pass. Owner approval, private downloads, native full submission, recovery trials, and remaining launch checks stay open.
- D1 stores metadata only. Private R2 payload generations and an authoritative retention marker prevent restored metadata from extending content retention. Migration 0003 applies to the empty live database.
- Only rebuilt artifacts can be reviewed. Malware failures and incomplete hard checks cannot be waived.
- The setup token has Workers AI Read, which supports inference. Workers AI Edit was rejected by automatic approval review and is unnecessary for the proven text call.
- Local-only policy exception is dated October 26, 2026 and limited to the explicit fixed-host SupportKit path.
- Backlink skill helper is absent at its documented path. Direct verification resolves edited wiki links to existing notes.
- No code has been pushed. The daily installed app and released download remain unchanged.
