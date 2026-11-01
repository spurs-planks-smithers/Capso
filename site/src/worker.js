// nextshot.dev: the download page for Nextshot.
//
// Static files (the page, the video) come from build/site, which
// site/deploy.sh stages. The DMGs and zips live in the private R2 bucket
// nextshot-releases (binding RELEASES). The record latest.json in that bucket
// says which version /download serves, so a release or a rollback changes it
// with no deploy (scripts/release.sh). This Worker runs first on every request
// so it can redirect www, count downloads, serve releases, render /stats, and
// add a noindex header.

import { LATEST_KEY, contentType, parseLatest, releaseKey, unsatisfiableRange } from "./releases.mjs";

// Bots, crawlers, link previews (Slack, Teams, Outlook), scripts, and the
// deploy smoke test. Their clicks are stored but shown apart from people.
const BOT_UA = /bot|crawl|spider|slurp|preview|facebookexternalhit|curl|wget|python|go-http|headless|nextshot-smoke-test/i;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.hostname === "www.nextshot.dev") {
      url.hostname = "nextshot.dev";
      return noindex(new Response(null, { status: 301, headers: { Location: url.toString() } }));
    }
    if (url.pathname === "/download") return noindex(await download(request, env, ctx));
    if (url.pathname === "/stats") return noindex(await stats(env));
    if (url.pathname === "/latest.json") return noindex(await latestJson(env));
    if (url.pathname.startsWith("/releases/")) {
      return noindex(await release(request, env, decodeName(url.pathname.slice("/releases/".length))));
    }
    const asset = await env.ASSETS.fetch(request);
    if (url.pathname === "/" || url.pathname === "/index.html") return noindex(await page(asset, env));
    return noindex(ranged(request, asset, sizeOf(env, url.pathname)));
  },
};

// The record that says which version /download serves, or null when R2 has
// none or it is not valid.
async function latestRecord(env) {
  const object = await env.RELEASES.get(LATEST_KEY);
  return object ? parseLatest(await object.text()) : null;
}

// The page has {{VERSION}} where the current version goes. It is filled per
// request, so a new release or a rollback shows on the page with no deploy.
async function page(asset, env) {
  if (asset.status !== 200) return asset;
  const latest = await latestRecord(env);
  const html = (await asset.text()).replaceAll("{{VERSION}}", esc(latest?.version));
  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-cache" },
  });
}

async function latestJson(env) {
  const latest = await latestRecord(env);
  if (!latest) return new Response("No release is published.\n", { status: 503, headers: { "Cache-Control": "no-store" } });
  return new Response(JSON.stringify(latest, null, 2) + "\n", {
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

// A file name from a path, or "" when it does not decode.
function decodeName(raw) {
  try {
    return decodeURIComponent(raw);
  } catch {
    return "";
  }
}

// One published file from R2, with Range and conditional requests. R2 reads
// the Range, If-Range, and If-None-Match headers itself and streams only the
// asked-for bytes. A name that is not a published file name gets a 404, and
// the name never reaches R2 as a path.
async function release(request, env, name) {
  const key = releaseKey(name);
  if (!key) return new Response("Not found\n", { status: 404 });
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed\n", { status: 405, headers: { Allow: "GET, HEAD" } });
  }

  const headers = new Headers({
    "Accept-Ranges": "bytes",
    "Content-Type": contentType(name),
    // A published file never changes under its name, but an hour keeps a
    // mistaken upload from sticking in caches.
    "Cache-Control": "public, max-age=3600",
  });
  if (!name.endsWith(".json") && !name.endsWith(".sha256")) {
    headers.set("Content-Disposition", `attachment; filename="${name}"`);
  }

  if (request.method === "HEAD") {
    const head = await env.RELEASES.head(key);
    if (!head) return new Response(null, { status: 404 });
    headers.set("ETag", head.httpEtag);
    headers.set("Content-Length", String(head.size));
    return new Response(null, { status: 200, headers });
  }

  // R2 sends the whole file for a range that starts past the end, so the
  // Worker checks first. This is the only extra R2 call, and only for ranges.
  const wanted = request.headers.get("Range");
  if (wanted) {
    const head = await env.RELEASES.head(key);
    if (!head) return new Response("Not found\n", { status: 404 });
    if (unsatisfiableRange(wanted, head.size)) {
      return new Response(null, { status: 416, headers: { "Content-Range": `bytes */${head.size}` } });
    }
  }

  const object = await env.RELEASES.get(key, { range: request.headers, onlyIf: request.headers });
  if (!object) return new Response("Not found\n", { status: 404 });

  headers.set("ETag", object.httpEtag);
  if (!object.body) return new Response(null, { status: 304, headers });
  if (object.range && request.headers.has("Range")) {
    const start = object.range.offset ?? 0;
    const end = object.range.length === undefined ? object.size - 1 : start + object.range.length - 1;
    headers.set("Content-Range", `bytes ${start}-${end}/${object.size}`);
    headers.set("Content-Length", String(end - start + 1));
    return new Response(object.body, { status: 206, headers });
  }
  headers.set("Content-Length", String(object.size));
  return new Response(object.body, { status: 200, headers });
}

// File sizes for the video. site/deploy.sh passes them as
// SIZES="/media/a.mp4=123", because the asset store's response does not
// expose Content-Length to the Worker.
function sizeOf(env, pathname) {
  for (const entry of (env.SIZES || "").split(",")) {
    const [path, bytes] = entry.split("=");
    if (path === pathname) return Number(bytes);
  }
  return 0;
}

// Safari plays a video only when the server answers a Range request with 206.
// When the asset store returns the whole file (200), stream only the asked-for
// bytes. The body is never held in memory.
function ranged(request, response, size) {
  if (request.method !== "GET" || response.status !== 200) return response;
  const match = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get("Range") || "");
  if (!match || (match[1] === "" && match[2] === "") || !size || response.headers.has("Content-Encoding")) {
    const out = new Response(response.body, response);
    if (size && !response.headers.has("Content-Encoding")) out.headers.set("Accept-Ranges", "bytes");
    return out;
  }
  let start = Number(match[1]);
  let end = match[2] === "" ? size - 1 : Math.min(Number(match[2]), size - 1);
  if (match[1] === "") {
    // Suffix range: the last N bytes.
    start = Math.max(0, size - Number(match[2]));
    end = size - 1;
  }
  if (start > end) {
    response.body?.cancel();
    return new Response(null, { status: 416, headers: { "Content-Range": `bytes */${size}` } });
  }
  const headers = new Headers(response.headers);
  headers.set("Accept-Ranges", "bytes");
  headers.set("Content-Range", `bytes ${start}-${end}/${size}`);
  const body = response.body.pipeThrough(byteSlice(start, end)).pipeThrough(new FixedLengthStream(end - start + 1));
  return new Response(body, { status: 206, headers });
}

// Passes on bytes start..end (inclusive) and stops reading after end.
function byteSlice(start, end) {
  let pos = 0;
  return new TransformStream({
    transform(chunk, controller) {
      const chunkStart = pos;
      pos += chunk.byteLength;
      if (pos > start) {
        controller.enqueue(chunk.subarray(Math.max(start - chunkStart, 0), Math.min(end + 1 - chunkStart, chunk.byteLength)));
      }
      if (pos > end) controller.terminate();
    },
  });
}

function noindex(response) {
  const out = new Response(response.body, response);
  out.headers.set("X-Robots-Tag", "noindex, nofollow");
  return out;
}

async function download(request, env, ctx) {
  const latest = await latestRecord(env);
  if (!latest) {
    return new Response("No release is published yet.\n", { status: 503, headers: { "Cache-Control": "no-store" } });
  }
  if (request.method === "GET") {
    const ua = request.headers.get("User-Agent") || "";
    const insert = env.DB.prepare("INSERT INTO downloads (at, version, country, is_bot) VALUES (?, ?, ?, ?)")
      .bind(new Date().toISOString(), latest.version, request.cf?.country ?? null, BOT_UA.test(ua) ? 1 : 0);
    // The redirect never waits for D1, and a failed write never blocks a download.
    ctx.waitUntil(insert.run().catch((err) => console.error("download insert failed", err)));
  }
  return new Response(null, {
    status: 302,
    headers: { Location: `/releases/${latest.file}`, "Cache-Control": "no-store" },
  });
}

async function stats(env) {
  const latest = await latestRecord(env);
  const [days, versions, totals] = await env.DB.batch([
    env.DB.prepare(
      "SELECT substr(at, 1, 10) AS label, SUM(is_bot = 0) AS people, SUM(is_bot) AS bots FROM downloads " +
        "WHERE at >= date('now', '-29 days') GROUP BY label ORDER BY label DESC"
    ),
    env.DB.prepare(
      "SELECT version AS label, SUM(is_bot = 0) AS people, SUM(is_bot) AS bots, MIN(at) AS first FROM downloads " +
        "GROUP BY version ORDER BY first DESC"
    ),
    env.DB.prepare("SELECT COUNT(*) - COALESCE(SUM(is_bot), 0) AS people, COALESCE(SUM(is_bot), 0) AS bots FROM downloads"),
  ]);
  const total = totals.results[0];
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Nextshot downloads</title>
<link rel="icon" href="/nextshot-icon.png">
<link rel="stylesheet" href="/site.css">
</head>
<body class="stats">
<main>
  <a class="brand" href="/"><img src="/nextshot-icon.png" alt="" width="32" height="32"><span>Nextshot downloads</span></a>
  <p class="total"><strong>${total.people}</strong> downloads by people, plus ${total.bots} from bots and link previews.</p>
  ${table("By version", "Version", versions.results)}
  ${dayChart(days.results)}
  <p class="meta">Current version: ${esc(latest?.version)}. <a href="/">Back to the download page</a></p>
</main>
</body>
</html>`;
  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function table(title, firstColumn, rows) {
  const body = rows.length
    ? rows.map((r) => `<tr><td>${esc(r.label)}</td><td>${r.people}</td><td>${r.bots}</td></tr>`).join("")
    : `<tr><td>n/a</td><td>0</td><td>0</td></tr>`;
  return `<section><h2>${title}</h2><table><thead><tr><th>${firstColumn}</th><th>People</th><th>${botsLabel("bots-info-table", "end")}</th></tr></thead><tbody>${body}</tbody></table></section>`;
}

// The last 30 UTC days as stacked columns, oldest on the left. D1 has no row
// for a day with no downloads, so that day shows as an empty column. The chart
// is hidden from screen readers, which read the same counts from a table.
function dayChart(rows) {
  const byLabel = new Map(rows.map((r) => [r.label, r]));
  const now = new Date();
  const days = [];
  for (let back = 29; back >= 0; back--) {
    const date = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - back));
    const label = date.toISOString().slice(0, 10);
    const row = byLabel.get(label);
    days.push({ date, label, people: row?.people ?? 0, bots: row?.bots ?? 0 });
  }
  const max = Math.max(...days.map((d) => d.people + d.bots));
  const step = axisStep(max);
  const top = Math.max(step, Math.ceil(max / step) * step);
  const grid = [];
  for (let value = 0; value <= top; value += step) {
    grid.push(`<div class="grid" style="bottom:${(value / top) * 100}%"><span>${value}</span></div>`);
  }
  const bars = days.map((d) => {
    const segments = [
      d.bots ? `<span class="bots" style="flex-grow:${d.bots}"></span>` : "",
      d.people ? `<span class="people" style="flex-grow:${d.people}"></span>` : "",
    ].join("");
    return `<div class="day" style="--h:${((d.people + d.bots) / top) * 100}%"><div class="stack">${segments}</div>` +
      `<div class="tip"><span class="tip-day">${shortDate(d.date, true)}</span>` +
      `<span><span class="key people"></span><strong>${d.people}</strong> people</span>` +
      `<span><span class="key bots"></span><strong>${d.bots}</strong> bots and previews</span></div></div>`;
  });
  // Labels on the first day, every seventh day, and today.
  const ticks = days.map((d, i) => `<span>${[0, 7, 14, 21, 29].includes(i) ? `<span>${shortDate(d.date)}</span>` : ""}</span>`);
  const rowsForReaders = days
    .map((d) => `<tr><td>${d.label}</td><td>${d.people}</td><td>${d.bots}</td></tr>`)
    .join("");
  return `<section class="by-day"><h2>By day, last 30 days (UTC)</h2>
  <div class="legend"><span><span class="swatch people"></span>People</span><span><span class="swatch bots"></span>${botsLabel("bots-info-chart", "start")}</span></div>
  <div class="chart" aria-hidden="true"><div class="plot">${grid.join("")}<div class="bars">${bars.join("")}</div></div><div class="ticks">${ticks.join("")}</div></div>
  <div class="sr-only"><table><caption>Downloads by day, oldest first</caption><thead><tr><th>Day</th><th>People</th><th>Bots and previews</th></tr></thead><tbody>${rowsForReaders}</tbody></table></div>
</section>`;
}

// The gridline step: the smallest of 1, 2, 5, 10, 20, 50, ... that splits the
// tallest day into four parts or fewer.
function axisStep(max) {
  for (let scale = 1; ; scale *= 10) {
    for (const base of [1, 2, 5]) if (base * scale * 4 >= max) return base * scale;
  }
}

function shortDate(date, weekday = false) {
  return date.toLocaleDateString("en-US", {
    timeZone: "UTC",
    month: "short",
    day: "numeric",
    ...(weekday ? { weekday: "short" } : {}),
  });
}

// "Bots and previews" with an info icon. Hover or keyboard focus opens a box
// that says what the column counts. The side says which edge the box lines up
// with, so it stays on the page.
function botsLabel(id, side) {
  return `<span class="info info-${side}">Bots and previews<button type="button" class="info-button" aria-label="What are bots and previews?" aria-describedby="${id}">${icon("info")}</button>` +
    `<span class="info-box" role="tooltip" id="${id}">` +
    `<span class="info-row">${icon("bot")}<span><strong>Bots</strong> are programs that open the download link with no person behind them. Examples are search crawlers, scripts, and the site's own deploy check.</span></span>` +
    `<span class="info-row">${icon("link")}<span><strong>Previews</strong> come from apps such as Slack, Teams, and Outlook. When someone pastes the link, the app opens it to draw a preview card.</span></span>` +
    `<span class="info-row">${icon("users")}<span><strong>Why it matters:</strong> neither one is a person who gets Nextshot. The page counts them apart, so People shows real downloads.</span></span>` +
    `<span class="info-note">The site sorts each request by its user agent (the name that a browser or app sends), so a few can land in the wrong column.</span>` +
    `</span></span>`;
}

// Lucide icons (lucide-static 0.460.0, ISC license), drawn inline.
const ICONS = {
  info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
  bot: '<path d="M12 8V4H8"/><rect width="16" height="12" x="4" y="8" rx="2"/><path d="M2 14h2"/><path d="M20 14h2"/><path d="M15 13v2"/><path d="M9 13v2"/>',
  link: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
};

function icon(name) {
  return `<svg class="icon" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name]}</svg>`;
}

function esc(value) {
  return String(value ?? "n/a").replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}
