# Feedback intake operations

Implementation plan: [[2026-10-26-secure-feedback-intake]]. Security rules: [[SECURITY_BASELINE]]. Service commands and bindings: `site/feedback/README.md`.

## Current launch state

The website intake runs at https://feedback.nextshot.dev/. Cloudflare Access protects `/review` and its child routes with the exact owner policy. The application also verifies the signed Access token. Owner sign-in and a rebuilt JPEG download pass without bypassing browser protections.

The base configuration remains closed. The explicit production profile reuses the approved private scanner digest. Website admission, processing, contextual checks, and fixed-recipient notifications are enabled. Native admission and inbound email remain disabled. Native app defaults remain off until the release owner activates them for 0.5.0 through [[2026-10-27-feedback-release-handoff]]. No production app is built by the website launch task.

The public human test receives receipt 086892f7, completes screening, prepares a private draft, and completes its notification send. The browser with automation attached returns Turnstile error 300030. After the owner disconnects automation, the normal browser verification and submission pass. Keep browser protections and server verification enabled. The form preserves accepted receipt messages after later challenge callbacks or status-poll outages.

The setup token expires on November 2, 2026. Runtime credentials remain resource bindings. The approved signature workflow runs on main with a bucket-only credential. The scheduled refresh and signature freshness pass.

The existing Nextshot deployment token cannot administer the new storage, Containers, Access, or Email Routing resources. Its existing release-bucket access remains unchanged. Use a separate feedback deployment credential. Store it as `CLOUDFLARE_API_TOKEN_NEXTSHOT_FEEDBACK` in Keychain. Never put a credential in chat.

Run the read-only permission probe:

```sh
python3 scripts/feedback-cloudflare-preflight.py
```

That probe reports API permissions and destination verification. It deliberately never reports full launch readiness. It does not mutate Cloudflare.

## Credential handling

Follow the local add-secret skill. Use `~/.dotfiles/claude-code/bin/keychain-store.sh` in Drew's terminal for credentials supplied by a provider. Verify length only. Put no values in source, a plan, a log, or a deployment argument.

The feedback deployment credential needs administration of the dedicated Worker, D1 database, queues, Containers, Access application, Turnstile, and nextshot.dev mail routing. Account billing must permit Workers Paid and Containers. Scope zone permissions to nextshot.dev. Runtime code receives resource bindings rather than that deployment credential.

The signature updater uses a separate credential with item access only to `nextshot-feedback-signatures`. Store its source credential in Keychain as `CLOUDFLARE_R2_TOKEN_NEXTSHOT_SIGNATURES`. Its GitHub Actions secret is `NEXTSHOT_SIGNATURES_API_TOKEN` in the `nextshot-feedback-signatures` environment. Restrict that environment's deployment branches to `main`. It receives no upload-store access.

The Worker needs `INTAKE_SECRET` and `TURNSTILE_SECRET` bindings. Generate the first as cryptographically random data. Store both source values in Keychain before wiring bindings. The service never uses an API key embedded in the Mac app.

Their source Keychain entries are `INTAKE_SECRET_NEXTSHOT_FEEDBACK` and `TURNSTILE_SECRET_NEXTSHOT_FEEDBACK`. Scripts pass them through process memory and stdin. This project has no plaintext environment file for intake secrets.

## Scanner artifacts

The source checkout contains no model weights. Meta requires approved download access. The private preparation tool pins the model revision and writes a file-hash manifest. Prepare its build context outside the Git checkout. Never add that context to Git.

The security/privacy page includes the required Built with Llama notice. Confirm the applicable model licenses before activation. Cloudflare's image model also needs its documented account activation.

The scanner uses no public internet access. Its fixed internal host reads immutable definition objects from the signature bucket. The updater is a separate trusted task with public internet access and no submissions.

The signed definition mirror is published and hash-verified. A real remote refresh succeeds with the separate bucket-only credential and closed stdin. The main-only environment and bucket-only secret are configured. Real manual and scheduled refreshes pass.

## Signature refresh

The workflow is `.github/workflows/feedback-signatures.yml`. It starts only when the repository variable `FEEDBACK_SIGNATURES_ENABLED` equals `true` and its bucket-only secret is configured.

Its schedule is 00:17, 02:17, and every two hours afterward in UTC. Pacific time is 17:17 on the previous day, 19:17, and every two hours afterward during daylight saving time. Standard time is one hour earlier. Scheduled and manual runs require `main`, and checkout explicitly selects `main`.

The publisher restores a hash-verified mirror seed when present. FreshClam verifies and refreshes the signed databases. All immutable objects upload before the manifest pointer changes. A failed refresh leaves the previous manifest authoritative. The scanner holds content when its freshness limit expires.

The task never waits for a person. Its regression tests use closed stdin and intercept only mirror delivery. Configure the first remote refresh and verify success before accepting public input.

## Launch sequence

1. Provision the dedicated bindings listed in the service README. Keep every R2 bucket private.
2. Configure owner-only Access for `/review` and its child routes. Set the exact audience and team domain.
3. Verify the Gmail destination. Onboard hi@nextshot.dev for authenticated sending.
4. Configure website Turnstile. Keep the native path anonymous with strict shared limits.
5. Supply approved classifier artifacts. Publish verified malware signatures.
6. Run synthetic EICAR, OCR, injection, privacy, network-denial, recovery, quota, and expiration checks in protected staging.
7. Confirm billing alerts at $25, $40, and $50. These enabled alerts measure account-wide usage charges and exclude recurring plan fees. The application budget is an estimate, not a provider billing cap.
8. Review the actual form, then enable website switches after its checks pass. Publish the homepage Feedback link. Verify a live receipt and protected review.
9. Use the separate 0.5.0 handoff for signed Dev app review, native transport checks, and native activation.
10. Enable exact-address inbound routing only after its separate attachment and delivery checks pass. Replace the null MX record at that point.

Use synthetic submissions for launch tests. Original attachments have no download route. Failed malware, structure, OCR, engine, or signature checks cannot be waived.

## Website operation and rollback

From the repository root, run `python3 site/feedback/deploy.py status` to verify the owner policy and read the live switches. Run `python3 site/feedback/deploy.py web` for website service updates before native activation. It keeps native and inbound mail off. Use the approved digest in `site/feedback/wrangler.production.jsonc`; model upgrades repeat the feasibility checks.

To stop intake, run `python3 site/feedback/deploy.py pause`. It disables new admission and processing starts. An in-flight scan can finish within its bounded attempt. The private review page and retention handler remain available. Verify `/config` reports disabled and new reservations return 503. Do not delete submissions or weaken Access during an incident.

Publish only the homepage and Guides with `site/deploy.sh --stage-only`, followed by `site/deploy.sh --deploy-staged <artifact>`. Use the existing pinned media. The command records a Worker rollback snapshot and restores it if site smoke checks fail. Compare `/latest.json` before and after. This operation must not change a released app record, file, or tag.

Native activation belongs to the separate 0.5.0 release runbook. The release owner enables the native backend with `python3 site/feedback/deploy.py native`, verifies a synthetic reduced package through screening, reviews the signed Dev app, and then freezes the release graph. After activation, use `native` for service updates that must retain native admission. A `web` deployment deliberately closes it.

Inbound email remains disabled. The apex null MX stays in place and the catchall stays off. Do not advertise hi@nextshot.dev until exact-address routing, attachment screening, and reconstructed delivery pass. There is no original-message forwarding fallback.

## Day-to-day review

Gmail receives screened plain text and an Access-protected review link. Suspected content receives a count and finding notification without excerpts. Personal Gmail replies expose Drew's address to the recipient.

Private review can inspect rebuilt material after required hard checks finish. A false-positive approval applies only to the exact submission, selected warning, and policy version. It reruns required controls. New findings hold again. Model-generated issue drafts inherit no exception and receive their own screening.

Held files expire 30 days after receipt. Screened files expire 90 days after receipt. Reprocessing does not restart retention. Delivered Gmail text follows Gmail's own settings.

D1 stores metadata only. Submission text, findings, drafts, and approvals live in versioned private R2 payloads. An R2 retention marker limits every payload generation and derivative. Restoring D1 metadata cannot extend that marker or recreate deleted content.

All bounded text receives contextual screening in overlapping chunks. Each chunk uses at most 8,000 JSON-escaped UTF-8 bytes, below the model's 24,000-token context. Draft input uses at most 12,000 serialized bytes. A longer submission still receives complete screening, but its automatic issue draft can be unavailable.

## Verification evidence

The website launch record is [[2026-10-27-feedback-public-launch]]. Earlier feasibility evidence is in [[2026-10-26-feedback-progress]]. Keep generated screenshots, audit outputs, and app builds under the project's ignored build folder. Never label a missing-engine check as passed.
