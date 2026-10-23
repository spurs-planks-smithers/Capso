# nextshot.dev

nextshot.dev is the one-page download site for Nextshot. People in internal organizations watch the intro video there and download the notarized DMG. It runs on Drew's Cloudflare account as one Worker with static assets and one D1 database, all on the free plan. Set up 2026-10-23.

## What it serves

| Path | What it does |
|---|---|
| `/` | The landing page: headline, video, Download button, install steps, and the footer "Free for personal use and internal use only." |
| `/download` | Stores one row in D1 (time, version, country, bot flag; no IP address), then redirects to the DMG |
| `/releases/<dmg>` | The notarized DMG under its versioned name |
| `/media/<video>.mp4` | The intro video. The Worker answers Range requests with 206, which Safari needs. It streams only the asked-for bytes and never holds a file in memory. |
| `/stats` | Download counts by day (last 30 days, UTC) and by version. People and bots show apart. Anyone with the link can open it. |
| `/LICENSE.txt` | Capso's Business Source License 1.1, copied from the repo `LICENSE`. The page does not link it. |
| `www.nextshot.dev/*` | 301 to `https://nextshot.dev/*` |

Every response carries `X-Robots-Tag: noindex, nofollow`, and the page has a matching robots meta tag. There is no `robots.txt` block, because a crawler that cannot fetch a page never sees its noindex tag (Google Search Central, "Block search indexing with noindex"). The page loads no analytics script, sets no cookies, and makes no third-party requests.

The bot flag comes from a user-agent pattern in `site/src/worker.js`: bots, crawlers, Slack, Teams, and Outlook link previews, curl, and the deploy smoke test (`nextshot-smoke-test`).

## Files

| Path | What it is |
|---|---|
| `site/wrangler.jsonc` | Worker `nextshot-site`: account, assets folder `../build/site`, D1 binding `DB`, custom domains |
| `site/src/worker.js` | The Worker. Plain JavaScript, no build step. |
| `site/schema.sql` | The `downloads` table |
| `site/public/` | `index.html` (with `{{...}}` placeholders) and `site.css` |
| `site/deploy.sh` | Stages `build/site`, deploys, and runs the smoke test |

`build/site` is generated and git-ignored, so the DMG and the video never reach git.

## Publish a change

```bash
site/deploy.sh
```

The script picks the newest `build/releases/Nextshot-20*.dmg` and the newest `build/releases/Nextshot-onboarding-20*.mp4`. It takes the video poster from the video itself, 3.5 seconds before the end. The repo poster PNG shows the email line "Get the DMG in this message", so the script does not use it. Flags override each input:

```bash
site/deploy.sh --video build/releases/<new cut>.mp4 --poster <image>
```

The script stops when the DMG has no stapled notarization ticket, when a file is 25 MiB or larger (the static asset limit), or when `LICENSE` is missing. After the deploy it checks the live site: page, noindex header, the `/download` redirect, the DMG SHA-256 hash, a video Range request (206), the www redirect, and `/stats`.

- New app build: run `scripts/release-notarized.sh`, then `site/deploy.sh`.
- New video cut: render it, then run `site/deploy.sh`.
- Local check: `site/deploy.sh --stage-only`, then start the `nextshot-site` entry in `.claude/launch.json` (`wrangler dev` on port 8787 with a local D1).

## Cloudflare access

- The deploy reads the account API token from the Keychain item `CLOUDFLARE_API_TOKEN_NEXTSHOT`, in memory only.
- Token permissions: Workers Scripts Edit, D1 Edit, Account Settings Read; on the nextshot.dev zone, Workers Routes Edit, DNS Edit, Zone Read.
- Revoke or roll it in the Cloudflare dashboard under Manage Account, Account API Tokens, `nextshot-site deploy`.
- `wrangler` itself stays signed out.

## Read the counts

Open `https://nextshot.dev/stats`, or query D1:

```bash
CLOUDFLARE_API_TOKEN="$(security find-generic-password -s CLOUDFLARE_API_TOKEN_NEXTSHOT -w)" wrangler d1 execute nextshot-downloads --remote --config site/wrangler.jsonc --command "SELECT version, SUM(is_bot = 0) AS people FROM downloads GROUP BY version"
```

## License

Capso's Additional Use Grant allows personal use, internal use within an organization, and non-commercial distribution. The page says "Free for personal use and internal use only." Keep the site free. Never add a price or a sign-up for paid use.

The license notice travels with the software: the DMG holds `LICENSE.txt` beside the app and inside it (`Contents/Resources/LICENSE.txt`). On 2026-10-23 Drew removed the page footer's Capso credit and license link. The BSL requires the notice on each copy of the software, not on a download page.
