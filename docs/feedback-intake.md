# Feedback intake operations

Implementation plan: [[2026-10-26-secure-feedback-intake]]. Security rules: [[SECURITY_BASELINE]]. Service commands and bindings: `site/feedback/README.md`.

## Current launch state

The implementation stays disabled until live verification completes. Local unit tests, a successful app build, and a successful container build do not establish production readiness.

The dedicated private storage, D1 schema, queues, Turnstile widget, Workers Paid plan, and owner Access application are provisioned. The setup token expires on November 2, 2026. Gmail ownership and pinned model artifacts are verified. The owner signs into the deployed review page successfully. Full live processing checks remain launch requirements.

Protected staging temporarily applies owner-only Access to the whole feedback hostname. All six intake switches remain false. Restore Access to `/review` and its children only after the public launch checks pass.

The existing Nextshot deployment token cannot administer the new storage, Containers, Access, or Email Routing resources. Its existing release-bucket access remains unchanged. Use a separate feedback deployment credential. Store it as `CLOUDFLARE_API_TOKEN_NEXTSHOT_FEEDBACK` in Keychain. Never put a credential in chat.

Run the read-only permission probe:

```sh
python3 scripts/feedback-cloudflare-preflight.py
```

That probe reports API permissions and destination verification. It deliberately never reports full launch readiness. It does not mutate Cloudflare.

## Credential handling

Follow the local add-secret skill. Use `~/.dotfiles/claude-code/bin/keychain-store.sh` in Drew's terminal for credentials supplied by a provider. Verify length only. Put no values in source, a plan, a log, or a deployment argument.

The feedback deployment credential needs administration of the dedicated Worker, D1 database, queues, Containers, Access application, Turnstile, and nextshot.dev mail routing. Account billing must permit Workers Paid and Containers. Scope zone permissions to nextshot.dev. Runtime code receives resource bindings rather than that deployment credential.

The signature updater uses a separate credential with item access only to `nextshot-feedback-signatures`. Store its source credential in Keychain as `CLOUDFLARE_R2_TOKEN_NEXTSHOT_SIGNATURES`. Its GitHub Actions secret is `NEXTSHOT_SIGNATURES_API_TOKEN`. It receives no upload-store access.

The Worker needs `INTAKE_SECRET` and `TURNSTILE_SECRET` bindings. Generate the first as cryptographically random data. Store both source values in Keychain before wiring bindings. The service never uses an API key embedded in the Mac app.

Their source Keychain entries are `INTAKE_SECRET_NEXTSHOT_FEEDBACK` and `TURNSTILE_SECRET_NEXTSHOT_FEEDBACK`. Scripts pass them through process memory and stdin. This project has no plaintext environment file for intake secrets.

## Scanner artifacts

The source checkout contains no model weights. Meta requires approved download access. The private preparation tool pins the model revision and writes a file-hash manifest. Prepare its build context outside the Git checkout. Never add that context to Git.

The security/privacy page includes the required Built with Llama notice. Confirm the applicable model licenses before activation. Cloudflare's image model also needs its documented account activation.

The scanner uses no public internet access. Its fixed internal host reads immutable definition objects from the signature bucket. The updater is a separate trusted task with public internet access and no submissions.

The signed definition mirror is published and hash-verified. A real remote refresh succeeds with the separate bucket-only credential and closed stdin. The recurring workflow remains disabled until its reviewed code and secret are configured in GitHub.

## Signature refresh

The workflow is `.github/workflows/feedback-signatures.yml`. It starts only when the repository variable `FEEDBACK_SIGNATURES_ENABLED` equals `true` and its bucket-only secret is configured.

Its schedule is 00:17, 02:17, and every two hours afterward in UTC. Pacific time is 17:17 on the previous day, 19:17, and every two hours afterward during daylight saving time. Standard time is one hour earlier.

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
8. Review the signed Dev app and the actual form. Enable the native flag only after review.
9. Enable service switches and exact-address mail routing only after the checks pass. Replace the null MX record at this point.
10. Publish the homepage Feedback link with the site deploy command. Verify live receipt, protected review, reconstructed mail, and expiry.

Use synthetic submissions for launch tests. Original attachments have no download route. Failed malware, structure, OCR, engine, or signature checks cannot be waived.

## Day-to-day review

Gmail receives screened plain text and an Access-protected review link. Suspected content receives a count and finding notification without excerpts. Personal Gmail replies expose Drew's address to the recipient.

Private review can inspect rebuilt material after required hard checks finish. A false-positive approval applies only to the exact submission, selected warning, and policy version. It reruns required controls. New findings hold again. Model-generated issue drafts inherit no exception and receive their own screening.

Held files expire 30 days after receipt. Screened files expire 90 days after receipt. Reprocessing does not restart retention. Delivered Gmail text follows Gmail's own settings.

D1 stores metadata only. Submission text, findings, drafts, and approvals live in versioned private R2 payloads. An R2 retention marker limits every payload generation and derivative. Restoring D1 metadata cannot extend that marker or recreate deleted content.

## Verification evidence

Record commands and final outcomes in [[2026-10-26-feedback-progress]]. Keep generated screenshots, audit outputs, and app builds under the project's ignored build folder. Never label a missing-engine check as passed.
