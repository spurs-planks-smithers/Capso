# nextshot.dev

nextshot.dev is the one-page download site for Nextshot. People in internal organizations watch the intro video there and download the notarized DMG. It runs on Drew's Cloudflare account as one Worker with static assets and one D1 database, all on the free plan. Set up 2026-10-23.

## What it serves

| Path | What it does |
|---|---|
| `/` | The landing page: the tagline "Show AI what you mean.", the intro video, the Download button, the round steps (Grab, Mark, Repeat, Hand off), install steps, and the footer "Free for personal use and internal use only." A slow gradient and an interactive dot field sit behind it (see "Page design"). |
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
| `site/public/` | `index.html` (with `{{...}}` placeholders), `site.css`, and `dots.js` (the background dot field). The deploy copies every file in this folder. |
| `site/deploy.sh` | Stages `build/site`, deploys, and runs the smoke test |

`build/site` is generated and git-ignored, so the DMG and the video never reach git.

## Publish a change

```bash
site/deploy.sh
```

The script picks the newest `build/releases/Nextshot-20*.dmg` and the newest `build/releases/Nextshot-onboarding-20*.mp4`, and skips the music option cuts (`-musicB.mp4`, `-musicC.mp4`). It takes the video poster from the video itself, 1 second before the end, where the end card is complete. Flags override each input:

```bash
site/deploy.sh --video build/releases/<new cut>.mp4 --poster <image>
```

The script stops when the DMG has no stapled notarization ticket, when a file is 25 MiB or larger (the static asset limit), or when `LICENSE` is missing. After the deploy it checks the live site: page, noindex header, the `/download` redirect, the DMG SHA-256 hash, a video Range request (206), the www redirect, and `/stats`.

- New app build: run `scripts/release-notarized.sh`, then `site/deploy.sh`.
- New video cut: render it, then run `site/deploy.sh`.
- Local check: `site/deploy.sh --stage-only`, then start the `nextshot-site` entry in `.claude/launch.json` (`wrangler dev` on port 8787 with a local D1).

## Page design

Redesigned 2026-10-24 for the v3.1 video, in the video's words: round, dot, one prompt.

- **Video first.** The video sits under the tagline, as wide as the window height allows, so the whole page fits a 1440 by 900 screen with no scroll. A "Watch the intro" button covers the poster, and the native controls appear once the video plays. Without JavaScript, the video keeps its controls.
- **Poster.** The site poster is a still made for the site: the lemonade page with red dots 1 to 3 on the left, and the open Nshot menu on the right with "Copy Prompt and End Round" highlighted (Drew, 2026-10-24: "The menu for Nextshot is key."). No single video frame shows both, so `make_poster.mjs` takes the zoomed hand-off menu and lays it over the Mark scene. Drew turned down the 56.8-second menu frame the same day, because its left half is empty. Until then the poster was the note panel frame at 46.6 seconds. The deploy's default poster is the end card, so make the still and pass it:

```bash
node scripts/video/nextshot-onboarding/make_poster.mjs build/site-poster.jpg
```

```bash
site/deploy.sh --video build/releases/Nextshot-onboarding-2026.10.24.mp4 --poster build/site-poster.jpg
```

- **Tagline.** "Show AI what you mean." with the line "Stop describing to AI what to fix. Start pointing at it." under it, and in the meta descriptions (Drew, 2026-10-24). It said "Visual feedback for AI coding agents, on your Mac." until then.
- **Download buttons.** Each place that offers the download (the header and under the video) has a Mac button and a Windows button of the same size, so neither ranks above the other (Drew, 2026-10-24). Mac is teal. Windows is gray, does not click, and carries a smaller "Coming soon" pill. Both show a download arrow icon so they read as download buttons. The icon is a plain arrow: Apple's trademark rules do not allow the Apple logo on third-party pages. On phones the header pair stacks under the brand.
- **Version line.** Under the buttons, only "Version 2026.10.24". The size, "macOS 15 or later", and "Notarized by Apple" are gone (Drew, 2026-10-24). `deploy.sh` still computes the size for its own output.
- **Gradient.** Teal light at the top left, indigo at the top right, and mint under the video, over graphite. It drifts over 48 seconds. All of it is CSS on `body::before`.
- **Dot field.** `dots.js` draws a 24-pixel grid of faint mint dots on one canvas. At rest the dots undulate in two slow, crossing waves. Under the pointer they brighten and part by up to 7 pixels. A moving pointer leaves a soft ripple about every 110 pixels, and a click or tap sends a ring outward at 560 pixels per second for 2.2 seconds. Drew asked for the effect after he saw a dot background in the Claude desktop app. Anthropic has published no description of that effect, so this one follows his description.
- **Cost.** The canvas draws at the display's frame rate only while something moves. At rest it draws 20 frames per second, and it stops while the tab is hidden. People who set Reduce Motion get a still grid and a still gradient.
- **Checks.** Run the `pdf-polish` wrap check on a local copy of the staged page at 1600, 1440, 1280, 1180, 1024, 768, and 390 pixels. All passed on 2026-10-24.
- **Test the motion in Playwright.** The Claude app's browser pane runs only about 2 animation frames per second while the pane is hidden, so a ripple never shows there.

## Cloudflare access

- The deploy reads the account API token from the Keychain item `CLOUDFLARE_API_TOKEN_NEXTSHOT`, in memory only.
- Token permissions: Workers Scripts Edit, D1 Edit, Account Settings Read; on the nextshot.dev zone, Workers Routes Edit, DNS Edit, Zone Read.
- Revoke or roll it in the Cloudflare dashboard under Manage Account, Account API Tokens, `nextshot-site deploy`.
- `wrangler` itself stays signed out.
- The zone's Minimum TLS Version is 1.2 (set 2026-10-24 in SSL/TLS, Edge Certificates). TLS 1.0 and 1.1 connections get a protocol-version alert. The token cannot change zone settings, so this one is a dashboard setting.

## Corporate web filters

On 2026-10-23, a few hours after launch, Nextiva-managed devices (m4max and a Windows PC) showed `NET::ERR_CERT_AUTHORITY_INVALID` with no way past it. The browser showed the issuer "Cisco Umbrella Secondary SubCA lax-SG". The real certificate (Google Trust Services WE1, chained to GTS Root R4 and cross-signed by GlobalSign Root CA) was valid from every other network tested.

- Cisco Umbrella on Nextiva devices stepped in for the new domain and served its own certificate. Every .dev domain is HSTS-preloaded, so Chrome shows a hard certificate error where Umbrella's block page would appear. Cisco documents this in [Troubleshoot HSTS and pinning](https://www.cisco.com/c/en/us/support/docs/security/umbrella/224686-troubleshoot-hsts-and-pinning.html).
- Umbrella's "Newly Seen Domains" category holds a domain for 24 hours after its first query ([Cisco](https://www.cisco.com/c/en/us/support/docs/security/umbrella/224735-enable-newly-seen-domains-security.html)). Other gateways treat a new domain as risky for longer: Palo Alto PAN-DB keeps "newly-registered-domain" for about 32 days.
- Check the reason on an affected device with `dig +short nextshot.dev`. Cloudflare addresses (104.21.92.146, 172.67.195.52) mean no DNS block. Umbrella block page addresses ([Cisco list](https://docs.umbrella.com/deployment-umbrella/docs/block-page-ip-addresses)): 146.112.61.110 is newly seen or a security block, .106 is a content category, .104 is a domain list.
- The lasting fix is an allow list entry for nextshot.dev in the organization's Umbrella policy. An admin can also dispute the category from Umbrella Activity Search, which sends it to Cisco Talos.
- Before sharing the link with another organization, ask its IT team to allow nextshot.dev, or wait until the domain is about 30 days old.
- The zone publishes "no mail" records: null MX (`0 .`), SPF `v=spf1 -all`, and DMARC `p=reject`. Nobody can send mail that passes as nextshot.dev.

## Read the counts

Open `https://nextshot.dev/stats`, or query D1:

```bash
CLOUDFLARE_API_TOKEN="$(security find-generic-password -s CLOUDFLARE_API_TOKEN_NEXTSHOT -w)" wrangler d1 execute nextshot-downloads --remote --config site/wrangler.jsonc --command "SELECT version, SUM(is_bot = 0) AS people FROM downloads GROUP BY version"
```

## License

Capso's Additional Use Grant allows personal use, internal use within an organization, and non-commercial distribution. The page says "Free for personal use and internal use only." Keep the site free. Never add a price or a sign-up for paid use.

The license notice travels with the software: the DMG holds `LICENSE.txt` beside the app and inside it (`Contents/Resources/LICENSE.txt`). On 2026-10-23 Drew removed the page footer's Capso credit and license link. The BSL requires the notice on each copy of the software, not on a download page.
