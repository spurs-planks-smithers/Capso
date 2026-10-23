// nextshot.dev: the download page for Nextshot.
//
// Static files (the page, the video, the DMG) come from build/site, which
// site/deploy.sh stages. This Worker runs first on every request so it can
// redirect www, count downloads, render /stats, and add a noindex header.
// DMG_FILE and VERSION come from `wrangler deploy --var`.

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
    if (url.pathname === "/download") return noindex(download(request, env, ctx));
    if (url.pathname === "/stats") return noindex(await stats(env));
    const asset = await env.ASSETS.fetch(request);
    return noindex(ranged(request, asset, sizeOf(env, url.pathname)));
  },
};

// File sizes for the video and the DMG. site/deploy.sh passes them as
// SIZES="/media/a.mp4=123,/releases/b.dmg=456", because the asset store's
// response does not expose Content-Length to the Worker.
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

function download(request, env, ctx) {
  if (request.method === "GET") {
    const ua = request.headers.get("User-Agent") || "";
    const insert = env.DB.prepare("INSERT INTO downloads (at, version, country, is_bot) VALUES (?, ?, ?, ?)")
      .bind(new Date().toISOString(), env.VERSION, request.cf?.country ?? null, BOT_UA.test(ua) ? 1 : 0);
    // The redirect never waits for D1, and a failed write never blocks a download.
    ctx.waitUntil(insert.run().catch((err) => console.error("download insert failed", err)));
  }
  return new Response(null, {
    status: 302,
    headers: { Location: `/releases/${env.DMG_FILE}`, "Cache-Control": "no-store" },
  });
}

async function stats(env) {
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
  <header class="brand"><img src="/nextshot-icon.png" alt="" width="32" height="32"><span>Nextshot downloads</span></header>
  <p class="total"><strong>${total.people}</strong> downloads by people, plus ${total.bots} from bots and link previews.</p>
  ${table("By day, last 30 days (UTC)", "Day", days.results)}
  ${table("By version", "Version", versions.results)}
  <p class="meta">Current version: ${esc(env.VERSION)}. <a href="/">Back to the download page</a></p>
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
  return `<section><h2>${title}</h2><table><thead><tr><th>${firstColumn}</th><th>People</th><th>Bots and previews</th></tr></thead><tbody>${body}</tbody></table></section>`;
}

function esc(value) {
  return String(value ?? "n/a").replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}
