// Make the nextshot.dev video poster: one 1920 by 1080 still that shows the
// lemonade page with its three red dots on the left and the open Nshot menu on
// the right (Drew, 2026-10-24). No single frame of the video shows both, so
// this script takes the hand-off menu state and lays it over the Mark scene.
//
//   node scripts/video/nextshot-onboarding/make_poster.mjs build/site-poster.jpg
//
// It reads timing.js, so run render.sh (or make_audio.py) first.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(process.argv[2] || "build/site-poster.jpg");
const chrome = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

// Fonts do not load from file URLs, so serve the folder on a local port.
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".png": "image/png",
  ".svg": "image/svg+xml", ".woff2": "font/woff2", ".ttf": "font/ttf", ".jpg": "image/jpeg" };
const server = http.createServer((req, res) => {
  const file = path.join(here, decodeURIComponent(new URL(req.url, "http://x").pathname));
  if (!file.startsWith(here) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404).end();
    return;
  }
  res.writeHead(200, { "Content-Type": types[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
});
await new Promise((ok) => server.listen(0, "127.0.0.1", ok));

const browser = await puppeteer.launch({ executablePath: chrome, headless: true });
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1920, height: 1080 });
  page.on("pageerror", (e) => console.error(`page error: ${e.message}`));
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html`, { waitUntil: "load" });
  // The composition builds its timeline in an inline script, so it is ready at load.
  await page.evaluate(() => document.fonts.ready);
  const stamp = await page.evaluate(() => {
    const tl = window.__timelines.root;
    const T = window.TIMING;
    const scene = (id) => T.scenes.find((s) => s.id === id);
    const $ = (s) => document.querySelector(s);

    // The hand-off menu, zoomed, with the cursor on a blue "Copy Prompt and
    // End Round" row. These times follow the hand-off code in index.html.
    const m0 = T.cues.menu;
    const arrive = Math.max(m0 + 0.75, Math.min(T.cues.copy - 0.2, m0 + 0.85));
    // After the click blink (copy + 0.02 to copy + 0.09) and before the menu closes (copy + 0.4).
    const handT = Math.max(arrive + 0.08, T.cues.copy + 0.15);
    tl.seek(handT, false);
    const keep = ["#menubar", "#menu", "#cursor", "#copyRow", "#copyRow .hk", "#nshotItem"];
    const saved = keep.map((s) => [s, $(s).getAttribute("style"), $(s).getAttribute("class")]);

    // The Mark scene just before Repeat: the lemonade page with dots 1 to 3.
    const markT = scene("how").end - 0.6;
    tl.seek(markT, false);
    for (const [s, style, cls] of saved) {
      $(s).setAttribute("style", style || "");
      if (cls) $(s).setAttribute("class", cls);
    }
    for (const s of ["#notePanel", "#captions", "#steps", "#keysS", "#lens"]) {
      $(s).style.visibility = "hidden";
    }
    return { handT: handT.toFixed(2), markT: markT.toFixed(2) };
  });
  await page.screenshot({ path: out, type: out.endsWith(".png") ? "png" : "jpeg", ...(out.endsWith(".png") ? {} : { quality: 90 }) });
  console.log(`poster ${out} (menu from ${stamp.handT} s over the Mark scene at ${stamp.markT} s)`);
} finally {
  await browser.close();
  server.close();
}
