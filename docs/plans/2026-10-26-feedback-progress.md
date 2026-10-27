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
| Integration | Root includes commits through 0ddf347. Policy exception, runbook, signature workflow, and homepage link are prepared locally. |
| Public launch | Disabled. No homepage deploy, native flag activation, or mail-routing activation. |

## Verified local behavior

| Check | Evidence |
| --- | --- |
| Service boundaries | 77 tests pass, including HTTPS, model contracts, restore-safe retention, and approval races. |
| Existing release site | 22 tests pass. /private/tmp/nextshot-site-tests-current.log |
| SupportKit | 6 tests pass. /private/tmp/nextshot-support-tests-current.log |
| FeedbackKit | 335 tests pass in native worktree verification. |
| JevKit Release | 369 tests pass in native worktree verification. |
| App tests | 247 tests pass. /private/tmp/nextshot-feedback-app-tests.log |
| Signed Dev app | Release build succeeds with Apple Development signature, no install. /private/tmp/nextshot-feedback-signed-build-final.log |
| Native UI | Real synthetic support panel rendered with 20 captures. No transport call or round data used. |
| Scanner | 61 tests pass inside the Linux image without network, with read-only root and 6 GiB memory. |
| Dependency audit | Actual image inventory: 38 distributions, zero known vulnerabilities, zero skips or suppressions. /private/tmp/nextshot-feedback-python-audit-image-patched.json |
| Actual scan engines | Real clean/injection classifier, full bounded text, signed ClamAV clean/EICAR, OCR credentials, and local network denial pass. build/feedback-checks/approved-engines-final.log |
| Largest standard export | Real full scans pass: standard 20 captures in 45.697 seconds; reduced 20 in 32.563 seconds. One CPU, no network, all engines. Neutral synthetic images do not prove worst-case content latency. build/feedback-checks/approved-full-scanner.json |
| Signature task | Five tests pass with stdin closed. Only final mirror delivery is intercepted. |
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

1. Complete real Cloudflare scanner network-denial, signature proxy, and full pipeline checks in protected staging.
2. Verify live reconstructed Gmail delivery, recovery, quotas, private file access, and expiry.
3. Configure recurring trusted signature refresh after code review and GitHub publication approval.
4. Configure exact-address inbound mail routing after the live scanner passes. Keep the catchall disabled.
5. Review the signed running Dev app and public form before enabling their launch switches.
6. Resolve the unpublished Guides base before preparing feedback publication. Preserve the already live Guides site.

## Live staging

- The dedicated Worker and private scanner image deploy successfully using durable-object scheduling.
- The container starts only through the fixed singleton. Its image digest is validated before startup. Internet access is explicitly disabled.
- All six service switches remain false. Native supportSubmission remains off.
- Disabled health/config checks and a rejected reservation pass. Review routes and forged-token attempts encounter Access.
- HSTS and insecure request guards deploy after the initial staging check finds HSTS absent.
- Drew signs into the actual review page on October 26, 2026. The owner list shows no submissions.
- Evidence: build/feedback-checks/staging-smoke-disabled.json and protected-staging-readiness.json.
- No homepage update or inbound mail route is active. No submission email is sent yet.

## Rulings and limits

- Engine substitutes never count as production scan evidence. All real local engines pass. Full live end-to-end feasibility remains unverified.
- D1 stores metadata only. Private R2 payload generations and an authoritative retention marker prevent restored metadata from extending content retention. Migration 0003 applies to the empty live database.
- Only rebuilt artifacts can be reviewed. Malware failures and incomplete hard checks cannot be waived.
- The setup token has Workers AI Read, which supports inference. Workers AI Edit was rejected by automatic approval review and is unnecessary for the proven text call.
- Local-only policy exception is dated October 26, 2026 and limited to the explicit fixed-host SupportKit path.
- Backlink skill helper is absent at its documented path. Direct verification resolves edited wiki links to existing notes.
- No code has been pushed. The daily installed app and released download remain unchanged.
