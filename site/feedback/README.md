# Nextshot feedback service

This Worker accepts website, native-app, and email submissions. It has no release-bucket or GitHub credentials. All launch switches are checked in as false.

## Local verification

```sh
npm ci --include=dev
npm test
npm run check
```

Run these commands from `site/feedback`. Node 22 or newer is required for the database-backed tests. `check` bundles the Worker and builds the scanner image. It does not deploy. Build scanner images on m5pro or a remote Linux builder. Device policy prevents Docker use on m4max.

The image built from the repository has no licensed classifier weights. It holds every submission until the approved model build context and fresh malware signatures are supplied. Never enable intake based on unit tests or a successful image build alone.

## Required resources

| Binding | Resource |
|---|---|
| DB | D1 `nextshot-feedback`; apply `schema.sql` |
| RAW | Private R2 `nextshot-feedback-raw` |
| REBUILT | Private R2 `nextshot-feedback-rebuilt` |
| SIGNATURES | Private R2 `nextshot-feedback-signatures` |
| JOBS | Queue `nextshot-feedback-scan` with `nextshot-feedback-dead` |
| SCANNER | One fixed `Scanner` Durable Object, fresh `standard-2` VM per attempt |
| AI | Cloudflare Workers AI |
| CONTACT_NOTIFY | Verified destination `drewschulz1@gmail.com` only |
| EDGE_LIMITER | 60 requests per minute per keyed IP identifier |

Use the provisioned D1 ID in configuration. A fresh database uses `schema.sql`. An empty database initialized with the original schema applies `migrations/0002_recovery_and_owner_review.sql`, then `migrations/0003_private_payloads.sql`, once in that order. Do not apply upgrades after loading the current schema. Migration 0003 refuses a nonempty database. It cannot remove plaintext from old database backups. A nonempty legacy database requires a separate content-migration decision before use. Keep all R2 public access disabled. Disable workers.dev and preview URLs. Configure Cloudflare Access for `/review` and `/review/*`, restricted to Drew. The application also verifies the JWT issuer, audience, signature, expiration, and exact email address.

Store `INTAKE_SECRET` and `TURNSTILE_SECRET` in the macOS Keychain and Worker secret bindings. `INTAKE_SECRET` needs at least 32 random characters. Never commit secret values. Set the public Turnstile site key, Access team domain, and Access audience in the deployed configuration.

Enable the public and native launch switches only after the live feasibility and owner-access checks pass. The six switches are `INTAKE_ENABLED`, `NATIVE_ENABLED`, `PROCESSING_ENABLED`, `AI_SCREENING_ENABLED`, `EMAIL_ENABLED`, and `NOTIFICATIONS_ENABLED`.

## Signature refresh

The separate trusted workflow `.github/workflows/feedback-signatures.yml` runs every two hours in UTC after `FEEDBACK_SIGNATURES_ENABLED=true` is set. Its `NEXTSHOT_SIGNATURES_API_TOKEN` can write only the signature bucket. It cannot read feedback uploads. The workflow calls `scripts/feedback-signatures.py`. Verify a successful remote refresh before launch.

The mirror uses `manifest.json` and immutable `definitions/<sha256>/<name>` objects. The scanner can read these only through its fixed internal signature hostname. It has no public egress. Missing, invalid, or stale definitions keep content held.

## API

1. `POST /v1/reservations` binds source, category, message, optional contact email, idempotency key, and each file's size/hash/type. Website submissions also supply a Turnstile token.
2. `PUT /v1/submissions/<id>/files/<file-id>` sends bytes with the returned Bearer token.
3. `POST /v1/submissions/<id>/complete` queues one immutable submission.
4. `GET /v1/submissions/<id>` returns only ID and processing status to the token holder.

Reservations permit new writes for ten minutes. Identical retries return the same IDs. Already-stored files acknowledge repeat uploads without overwriting or reopening them. Receipt tokens grant no file download access.

The owner page exposes rebuilt JPEGs after screening completes. It also permits private inspection of held derivatives only after every required file, OCR, classifier, and contextual check completes. Original uploads have no download route. Owner approval selects exact false-positive findings. It binds the actor, content fingerprint, policy version, and a maximum 24-hour expiry. Every check runs again. New findings remain held. Malware, failed or incomplete engines, uncertain results, and prohibited content cannot be approved. Issue-draft output inherits no approval.

## Limits and retention

Admission starts at five submissions per hour and twenty per day per keyed IP identifier. File limits are two per hour, ten per day, and fifty globally per day. Global intake is one hundred submissions per day. Email has separate sender and channel limits; sender identity is only a weak abuse signal.

Each scan reserves a conservative cost estimate before work begins. A $35 variable-work allowance plus the $5 plan minimum pauses processing near $40. Reservations are not refunded. This can pause work before actual costs reach $40. Provider billing alerts at $25, $40, and $50 remain a separate launch requirement. This is not a provider billing cap.

Held material expires thirty days after receipt. Screened material expires ninety days after receipt. D1 stores only metadata, cryptographic hashes, and opaque pointers. Submitted text, contact details, findings, owner approvals, and drafts live in immutable private R2 payload records. Each generation is tracked before storage. A conditional D1 pointer update publishes one generation. Losing generations remain tracked until expiration. D1 Time Travel can retain metadata for thirty days after deletion, but it contains no submitted content.

A separate R2 retention marker controls every payload, original, upload attempt, and rebuilt file. It starts at receipt plus thirty days. Only a completed screened publication promotes it to receipt plus ninety days. Reads use the earlier of the SQL deadline and the R2 deadline. Missing markers, missing payloads, wrong hashes, and unconfirmed publication fail closed. Final SQL publication must clear its lease under the current scan claim before that lease expires. Public screened reads require that completed publication. An interrupted final publication requires a full recheck. Maintenance does not infer completion from database metadata or a retention marker. Restoring D1 cannot recreate a marker or extend a held deadline. Maintenance first claims an expired marker with a conditional write. It then sweeps all submission prefixes, including generations absent from restored SQL. A separate cursor-based sweep removes late orphan writes. The marker is deleted last. The hourly maintenance handler deletes raw objects, every upload attempt, all rebuilt artifact generations, content, drafts, and audit rows. Interrupted upload and notification claims have recovery deadlines. Upload retries verify stored bytes before recovery. Notifications can duplicate after uncertain delivery; they are retried instead of silently lost. Scanner publication requires its current ownership nonce and live lease. A stale scan cannot change a replacement result or expose its artifacts. Queue messages contain IDs only. Retries do not extend expiration. Delivered Gmail text follows Gmail's retention settings.

## Inbound email

Route only `hi@nextshot.dev` to this Worker. Enable no catchall. Replace the existing null MX record only during the verified mail setup. Configure the required SPF, DKIM, and DMARC records for the onboarded service.

The Worker reads at most 15 megabytes of raw MIME and accepts at most 10 megabytes of allowed attachments. Unsupported inline or ordinary attachments hold the whole message. Original messages are never forwarded. Notifications are rebuilt plain text with a fixed recipient. No automatic response goes to submitted addresses.

## Before public launch

Prove EICAR detection, real OCR, pinned Prompt Guard inference, all hosted model calls, network denial, owner-only file access, Gmail delivery, cost reservation, and deletion against the live staging stack. Use synthetic data. A missing check keeps launch switches false.
