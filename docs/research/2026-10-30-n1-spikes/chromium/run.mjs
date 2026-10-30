// N1 spike 3 and 1: real Chromium engine lifecycle (Chrome for Testing, fixture tier).
// Usage: node run.mjs <bin folder with spike-app and spike-host> <work folder>
// Needs playwright-core (any copy) on NODE_PATH or in an ancestor node_modules.
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const [bin, work] = process.argv.slice(2);
// PLAYWRIGHT_CORE is the path to a playwright-core copy's index.mjs; CFT_PATH is Chrome for Testing's executable.
const { chromium } = await import(process.env.PLAYWRIGHT_CORE);
const here = path.dirname(fileURLToPath(import.meta.url));
const chromePath = process.env.CFT_PATH;
const results = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const report = (name, data) => { results.push({ name, ...data }); console.log(JSON.stringify({ name, ...data })); };
const pids = (pattern) => spawnSync('pgrep', ['-f', pattern]).stdout.toString().split('\n').filter(Boolean).map(Number);
const hostPids = () => pids(`${bin}/spike-host`);

fs.mkdirSync(work, { recursive: true });
const userData = path.join(work, 'profile');
fs.rmSync(userData, { recursive: true, force: true });
const pidFile = path.join(work, 'app.pid');
const wrapper = path.join(work, 'host-wrapper.sh');
fs.writeFileSync(wrapper, `#!/bin/bash\nexec "${bin}/spike-host" "$1" "$(cat "${pidFile}")" com.drewschulz.nextshot.dev.spike-app "${bin}/spike-app"\n`, { mode: 0o755 });

const server = http.createServer((req, res) => { res.setHeader('content-type', 'text/html'); res.end('<title>fixture</title><h1>fixture page</h1>'); });
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

const context = await chromium.launchPersistentContext(userData, {
  executablePath: chromePath, headless: true, ignoreDefaultArgs: ['--disable-extensions'],
  args: [`--disable-extensions-except=${path.join(here, 'ext')}`, `--load-extension=${path.join(here, 'ext')}`],
});
let worker = context.serviceWorkers()[0] ?? await context.waitForEvent('serviceworker', { timeout: 15000 });
const id = new URL(worker.url()).host;
report('setup', { extensionId: id, browser: context.browser()?.version?.() ?? 'persistent', fixturePort: port });

const hostDir = path.join(userData, 'NativeMessagingHosts');
fs.mkdirSync(hostDir, { recursive: true });
const manifest = (name, p, origins) => fs.writeFileSync(path.join(hostDir, `${name}.json`),
  JSON.stringify({ name, description: 'N1 spike', path: p, type: 'stdio', allowed_origins: origins }));
manifest('com.nextshot.spike', wrapper, [`chrome-extension://${id}/`]);
manifest('com.nextshot.spike.forbidden', wrapper, ['chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/']);
manifest('com.nextshot.spike.stale', path.join(work, 'missing-helper'), [`chrome-extension://${id}/`]);

const control = await context.newPage();
await control.goto(`chrome-extension://${id}/page.html`);
// Fire and forget: a reply is not needed (the worker logs to storage), and a message that races
// with worker shutdown or restart never answers. The caller reads the log instead.
const call = async (message) => {
  await control.evaluate((m) => { window.call(m).catch(() => {}); }, message);
  await sleep(600);
};
process.on('uncaughtException', (error) => { console.log(JSON.stringify({ name: 'fatal', error: String(error).slice(0, 300) })); spawnSync('pkill', ['-9', '-f', userData]); spawnSync('pkill', ['-9', '-f', `${bin}/spike-`]); process.exit(1); });
const readLog = () => control.evaluate(() => window.readLog());
const starts = async () => (await readLog()).filter((e) => e.kind === 'worker-start').length;

// Absent, forbidden and stale host: the error text an extension sees.
for (const name of ['com.nextshot.nope', 'com.nextshot.spike.forbidden', 'com.nextshot.spike.stale']) {
  const before = (await readLog()).length;
  await call({ op: 'connect', name });
  await sleep(1500);
  const entries = (await readLog()).slice(before);
  report(`native-host-state:${name}`, { events: entries.map(({ kind, error }) => ({ kind, error })) });
}

// Gesture and grant: the same message path (not an action click) with and without a site grant.
const granted = await context.newPage(); await granted.goto(`http://127.0.0.1:${port}/`);
const notGranted = await context.newPage(); await notGranted.goto(`http://localhost:${port}/`);
const tabs = await control.evaluate(() => chrome.tabs.query({}).then((t) => t.map(({ id, url }) => ({ id, url }))));
for (const tab of tabs.filter((t) => t.url.startsWith('http'))) {
  const before = (await readLog()).length;
  await call({ op: 'script', tabId: tab.id, url: tab.url });
  await sleep(500);
  report(`executeScript-without-gesture:${new URL(tab.url).hostname}`, { events: (await readLog()).slice(before).map(({ kind, error, result }) => ({ kind, error, result })) });
}
await granted.bringToFront();
{
  const before = (await readLog()).length;
  await call({ op: 'capture' });
  await sleep(800);
  report('captureVisibleTab-from-message-not-gesture', { events: (await readLog()).slice(before).map(({ kind, error, bytes }) => ({ kind, error, bytes })) });
}

// Baseline: with no native port, does the worker stop after about 30 s idle (so a later message restarts it)?
console.log(JSON.stringify({ phase: 'baseline-idle-start', at: Date.now() }));
const startsBefore = await starts();
const idleStart = Date.now();
await sleep(Number(process.env.BASELINE_IDLE_MS ?? 45000));
console.log(JSON.stringify({ phase: 'baseline-idle-done', at: Date.now() }));
await call({ op: 'post', body: {} });
await sleep(500);
report('worker-idle-baseline-no-port', { idleMs: Date.now() - idleStart, workerStartsBefore: startsBefore, workerStartsAfter: await starts(),
  note: 'after > before means the worker was stopped while idle and restarted by the message' });

// Held port: app running, host launched by Chrome through connectNative.
const app = spawn(`${bin}/spike-app`, ['com.drewschulz.nextshot.dev.spike-host', `${bin}/spike-host`, '600'], { stdio: ['pipe', 'pipe', 'inherit'] });
const appLines = []; readline.createInterface({ input: app.stdout }).on('line', (l) => appLines.push({ at: Date.now(), ...JSON.parse(l) }));
await sleep(800);
fs.writeFileSync(pidFile, String(app.pid));
const opened = Date.now();
await call({ op: 'connect', name: 'com.nextshot.spike' });
await call({ op: 'post', body: { op: 'open' } });
await sleep(1500);
const hostsWhileOpen = hostPids();
const startsAtOpen = await starts();
const holdMs = Number(process.env.HOLD_MS ?? 75000);
await sleep(holdMs);
const heldLog = await readLog();
app.stdin.write('cmd frames\n');
await sleep(800);
const afterCmd = await readLog();
report('held-native-port', { hostProcessesWhileOpen: hostsWhileOpen.length, holdMs, workerStartsAtOpen: startsAtOpen, workerStartsAfterHold: await starts(),
  readyReceived: heldLog.some((e) => e.kind === 'native-message' && e.body?.type === 'ready'),
  commandReachedExtensionAfterIdle: afterCmd.some((e) => e.kind === 'native-message' && e.body?.type === 'command'),
  hostStillRunningAfterHold: hostPids().length === hostsWhileOpen.length,
  appEvents: appLines.map(({ ev, ms }) => ({ ev, ms })) });

// Teardown by extension disconnect.
let t = Date.now();
await call({ op: 'disconnect' });
while (hostPids().length && Date.now() - t < 5000) await sleep(10);
report('teardown:extension-disconnect', { hostGoneMs: hostPids().length ? null : Date.now() - t, appSessionEnded: appLines.filter((e) => e.ev === 'session-ended').map(({ reason }) => reason) });

// Teardown by extension reload (worker and port die together).
await call({ op: 'connect', name: 'com.nextshot.spike' });
await call({ op: 'post', body: { op: 'open' } });
await sleep(1500);
const hostBeforeReload = hostPids().length;
t = Date.now();
await call({ op: 'reload' }).catch(() => {});
while (hostPids().length && Date.now() - t < 8000) await sleep(10);
report('teardown:extension-reload', { hostsBefore: hostBeforeReload, hostGoneMs: hostPids().length ? null : Date.now() - t, appSessionEnded: appLines.filter((e) => e.ev === 'session-ended').map(({ reason }) => reason) });

// Teardown by browser process kill. Reconnect first (the reload ended the worker).
await sleep(1500);
const page2 = (await context.pages()).find((p) => p.url().startsWith('chrome-extension://')) ?? await context.newPage();
await page2.goto(`chrome-extension://${id}/page.html`);
await page2.evaluate(() => window.call({ op: 'connect', name: 'com.nextshot.spike' }));
await page2.evaluate(() => window.call({ op: 'post', body: { op: 'open' } }));
await sleep(1500);
const hostBeforeKill = hostPids().length;
const mainPid = pids(userData).sort((a, b) => a - b)[0];
t = Date.now();
process.kill(mainPid, 'SIGKILL');
while (hostPids().length && Date.now() - t < 8000) await sleep(10);
report('teardown:browser-sigkill', { hostsBefore: hostBeforeKill, hostGoneMs: hostPids().length ? null : Date.now() - t,
  appSessionEnded: appLines.filter((e) => e.ev === 'session-ended').map(({ reason }) => reason) });

app.kill('SIGKILL'); server.close();
spawnSync('pkill', ['-9', '-f', userData]);
fs.writeFileSync(path.join(work, 'chromium-results.json'), JSON.stringify(results, null, 2));
process.exit(0);
