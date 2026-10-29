# Browser Jev client integration

`src/jev-client.ts` provides the isolated text-only C7 client. It mirrors `site/jev/src/policy.js` and the service routes. This module makes no request when imported. No provider secret belongs in browser code. Keep this work in Later and outside v0.5.0.

## Trusted owner

Create one `createJevClient()` instance in the service worker. Route only messages from known extension pages. Do not route content-script messages to its methods. Never return tokens or storage data to message callers. Central ownership serializes single-use refresh credentials across simultaneous review requests.

Tokens use `chrome.storage.local` with `TRUSTED_CONTEXTS` access. They survive service-worker suspension and browser restarts. Refresh credentials expire 30 days after explicit sign-in. No credentials enter round records, export bundles, or page-accessible storage. Sign Out clears the stored credentials.

## UI and permissions

The UI owner adds the optional `identity` permission to the manifest. Request it during an explicit Sign In action. Request optional host access to `https://jev.nextshot.dev/*` during deliberate enablement. The existing wildcard optional host declaration permits this narrow request. Do not request access during capture, tracking, or save.

Keep three independent policy settings in trusted extension preferences. Each defaults to false: `jevEnabled`, `jevConsentPageData`, and `jevConsentReviewerText`. Successful sign-in must not change these settings. The client treats absent or non-true settings as disabled.

Before enablement, disclose that selected sanitized page evidence leaves the browser. Separately ask permission for reviewer notes. Explain that TypeSafe may retain requests. Stills stay local with this provider contract. Never send animation, audio, full document content, URLs, locators, headers, or bodies.

## API

- `signIn()` opens an interactive Chrome identity flow. Call it only from an explicit Sign In action. It returns `{signedIn}`. It verifies the fixed redirect, state, issuer, and PKCE challenge binding. It does not enable assistance.
- `signOut()` clears local credentials and attempts bounded server revocation. It can silently refresh an expired access token first. Failed or uncertain refresh delivery discards credentials. No refresh token is replayed.
- `status()` reads local authentication state. It returns `signedIn`, `needsReconnect`, and `accessExpired`. It makes no network request and does not report live allowance.
- `refine(selection, policy, {signal, stillCurrent, deadlineMs})` returns candidates or `{available:false, fallback:'local', reason}`. The default deadline is 1000 milliseconds. A caller can shorten it but cannot lengthen it.

`selection` holds purpose (`steps` or `elements`), stable logical `requestID`, `selectionVersion`, timeline, diagnostics, candidates, and an optional reviewer note. The exact exported TypeScript types define each row. The note is omitted unless reviewer-text consent is true. All rows use the service bounds and deny extra fields. The service reserves cost before paid processing. The browser never retries a refinement request automatically.

The result contains only supplied IDs and confidence values. A steps reply refers to timeline IDs. An elements reply refers to candidate IDs. Unknown fields, invented IDs, duplicates, invalid confidence, and mismatched request/version/purpose produce local fallback. Generated wording cannot enter the result.

Prepare local suggestions first. Start refinement only during deliberate review. Do not await refinement from save. Pass an AbortSignal for closed or canceled drafts. `stillCurrent()` must check the current selection version and preserve reviewer edits, accepted steps, selected issues, and chosen excerpts. Change that revision whenever any of these change. Apply a result only if this condition still holds when the caller receives it. Each request captures its immutable payload and identity before awaiting work.

A canceled review can finish a shared token refresh, but it sends no subsequent refinement request. The client stops applying late replies. Cancellation cannot recall data already delivered to the service.

## Local evidence and remaining acceptance

The existing `npm run check` and `npm run build` commands validate the module. A scratch mock exercises PKCE/state/redirect checks, single refresh under concurrency, consent gates, payload exclusions, stale/canceled replies, malformed responses, and offline/capped/provider fallback. These checks use no live service, identity provider, or paid call.

Real invited sign-in, extension permission behavior, revocation, provider retention disclosure, live allowance fallback, and suggestion quality require the integrated browser UI and service activation evidence. Keep the flag off until Dev review. No deployment or paid request is part of this module change.
