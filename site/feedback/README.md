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
| SCANNER | One `Scanner` container, `standard-2` |
| AI | Cloudflare Workers AI |
| CONTACT_NOTIFY | Verified destination `drewschulz1@gmail.com` only |
| EDGE_LIMITER | 60 requests per minute per keyed IP identifier |

Replace the zero D1 ID after provisioning. Keep all R2 public access disabled. Disable workers.dev and preview URLs. Configure Cloudflare Access for `/review` and `/review/*`, restricted to Drew. The application also verifies the JWT issuer, audience, signature, expiration, and exact email address.

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

The owner page exposes only rebuilt JPEGs after screening completes. Original uploads have no download route. Requesting a recheck reruns all controls and never bypasses a malware or file-validation failure.

## Limits and retention

Admission starts at five submissions per hour and twenty per day per keyed IP identifier. File limits are two per hour, ten per day, and fifty globally per day. Global intake is one hundred submissions per day. Email has separate sender and channel limits; sender identity is only a weak abuse signal.

Each scan reserves a conservative cost estimate before work begins. A $35 variable-work allowance plus the $5 plan minimum pauses processing near $40. Reservations are not refunded. This can pause work before actual costs reach $40. Provider billing alerts at $25, $40, and $50 remain a separate launch requirement. This is not a provider billing cap.

Held material expires thirty days after receipt. Screened material expires ninety days after receipt. The hourly maintenance handler deletes raw objects, rebuilt objects, content, drafts, and audit rows. Queue messages contain IDs only. Retries do not extend expiration. Delivered Gmail text follows Gmail's retention settings.

## Inbound email

Route only `hi@nextshot.dev` to this Worker. Enable no catchall. Replace the existing null MX record only during the verified mail setup. Configure the required SPF, DKIM, and DMARC records for the onboarded service.

The Worker reads at most 15 megabytes of raw MIME and accepts at most 10 megabytes of allowed attachments. Unsupported inline or ordinary attachments hold the whole message. Original messages are never forwarded. Notifications are rebuilt plain text with a fixed recipient. No automatic response goes to submitted addresses.

## Before public launch

Prove EICAR detection, real OCR, pinned Prompt Guard inference, all hosted model calls, network denial, owner-only file access, Gmail delivery, cost reservation, and deletion against the live staging stack. Use synthetic data. A missing check keeps launch switches false.
