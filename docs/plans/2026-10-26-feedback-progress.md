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
| Scanner | Strict archive schemas, ClamAV, image rebuilding, OCR, privacy rules, pinned Prompt Guard loader, hard timeouts, and restricted network path implemented. Approved model weights remain absent. |
| Recovery | Immutable upload attempts, leased scan/notification claims, and generation-bound review approvals implemented. |
| Integration | Root includes commits through af38471. Policy exception, runbook, signature workflow, and homepage link are prepared locally. |
| Public launch | Disabled. No homepage deploy, native flag activation, or mail-routing activation. |

## Verified local behavior

| Check | Evidence |
| --- | --- |
| Service boundaries | 39 tests pass. /private/tmp/nextshot-feedback-service-tests-current.log |
| Existing release site | 22 tests pass. /private/tmp/nextshot-site-tests-current.log |
| SupportKit | 6 tests pass. /private/tmp/nextshot-support-tests-current.log |
| FeedbackKit | 335 tests pass in native worktree verification. |
| JevKit Release | 369 tests pass in native worktree verification. |
| App tests | 247 tests pass. /private/tmp/nextshot-feedback-app-tests.log |
| Signed Dev app | Release build succeeds with Apple Development signature, no install. /private/tmp/nextshot-feedback-signed-build-final.log |
| Native UI | Real synthetic support panel rendered with 20 captures. No transport call or round data used. |
| Scanner | 50 tests pass inside the Linux image without network, with read-only root and 6 GiB memory. |
| Dependency audit | Actual image inventory: 38 distributions, zero known vulnerabilities, zero skips or suppressions. /private/tmp/nextshot-feedback-python-audit-image-patched.json |
| Actual scan engines | Real signed ClamAV clean/EICAR detection and real OCR privacy detection pass. build/feedback-checks/actual-engine-check.json |
| Largest standard export | 20 captures, 40 JPEGs, 63 archive entries: hard scan phases finish in 30.43 seconds on one CPU. Model time excluded. /private/tmp/nextshot-feedback-batch-benchmark-full.json |
| Signature task | Five tests pass with stdin closed. Only final mirror delivery is intercepted. |
| Worker build | Wrangler bundle and Docker dry-run pass. /private/tmp/nextshot-feedback-root-bundle.log |

## Cloudflare setup

- User stores the seven-day setup token in Keychain as CLOUDFLARE_API_TOKEN_NEXTSHOT_FEEDBACK. Expiry: November 2, 2026.
- Three private R2 buckets exist: nextshot-feedback-raw, nextshot-feedback-rebuilt, and nextshot-feedback-signatures. Public access and custom domains are absent.
- D1 nextshot-feedback exists with current schema and seven tables. ID: 08e03222-27df-4ac6-947a-3e0586f2c7a0.
- Dedicated scan and dead-letter queues exist.
- Managed Turnstile widget is restricted to feedback.nextshot.dev. Its secret and the generated intake secret live in Keychain.
- User activates Workers Paid. Containers API access now passes.
- Enabled account usage alerts exist at $25, $40, and $50. They exclude recurring plan fees and impose no cap. The prior $10 alert stays enabled.
- Mistral text inference succeeds with synthetic input. Meta vision inference returns license-required error 5016.
- Gmail destination is added. Ownership verification remains required.
- Access Free checkout is prepared. User activation remains pending.
- Source resource report: build/feedback-checks/cloudflare-resources.json. Current preflight: build/feedback-checks/cloudflare-preflight-current.json.

## Required before launch

1. Activate owner Access and verify application-boundary token checks in protected staging.
2. Verify the Gmail destination and authenticate exact-address mail routing.
3. Obtain approved pinned Prompt Guard artifacts and activate the hosted vision model under its applicable license.
4. Configure the separate bucket-only signature updater credential and prove a remote refresh.
5. Complete real Cloudflare scanner isolation, models, latency, cost, delivery, recovery, quota, and expiry checks.
6. Resolve D1 Time Travel content retention. Paid backups retain deleted rows for up to 30 additional days. Do not promise erasure of those copies without a technical control or an approved policy change.
7. Review the signed running Dev app and public form before enabling their launch switches.

## Rulings and limits

- Engine substitutes never count as production scan evidence. The classifier and full end-to-end feasibility remain unverified.
- Only rebuilt artifacts can be reviewed. Malware failures and incomplete hard checks cannot be waived.
- The setup token has Workers AI Read, which supports inference. Workers AI Edit was rejected by automatic approval review and is unnecessary for the proven text call.
- Local-only policy exception is dated October 26, 2026 and limited to the explicit fixed-host SupportKit path.
- Backlink skill helper is absent at its documented path. Direct verification resolves edited wiki links to existing notes.
- No code has been pushed. The daily installed app and released download remain unchanged.
