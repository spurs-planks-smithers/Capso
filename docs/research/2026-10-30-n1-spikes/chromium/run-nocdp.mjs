// N1 spike 3, no-debugger variant (Chrome for Testing, fixture tier).
// The extension drives itself with alarms; this script only starts the browser, the app
// stand-in, and watches processes and the log file. Nothing attaches to the worker.
// Usage: node run-nocdp.mjs <bin folder> <work folder>   Env: CFT_PATH
import { spawn, spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const [bin, work] = process.argv.slice(2);
const here = path.dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pids = (args) => spawnSync('pgrep', args).stdout.toString().split('\n').filter(Boolean).map(Number);
const hostRunning = () => pids(['-x', 'spike-host']).length;

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });
// Copy the extension and give it a fixed key so the extension ID is known before launch.
const extDir = path.join(work, 'ext');
fs.cpSync(path.join(here, 'ext2'), extDir, { recursive: true });
const { publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const der = publicKey.export({ type: 'spki', format: 'der' });
const id = [...crypto.createHash('sha256').update(der).digest('hex').slice(0, 32)].map((c) => String.fromCharCode(97 + parseInt(c, 16))).join('');
fs.writeFileSync(path.join(extDir, 'manifest.json'), JSON.stringify({
  manifest_version: 3, name: 'N1 spike (self-driven)', version: '0.0.1', key: der.toString('base64'),
  permissions: ['nativeMessaging', 'alarms'], background: { service_worker: 'sw.js' },
}, null, 2));

const profile = path.join(work, 'profile');
const hostDir = path.join(profile, 'NativeMessagingHosts');
fs.mkdirSync(hostDir, { recursive: true });
const pidFile = path.join(work, 'app.pid');
const eventsFile = path.join(work, 'events.jsonl');
const heldWrapper = path.join(work, 'held.sh');
const loggerWrapper = path.join(work, 'logger.sh');
fs.writeFileSync(heldWrapper, `#!/bin/bash\nexec "${bin}/spike-host" "$1" "$(cat "${pidFile}")" com.drewschulz.nextshot.dev.spike-app "${bin}/spike-app"\n`, { mode: 0o755 });
fs.writeFileSync(loggerWrapper, `#!/bin/bash\nexec /usr/bin/python3 -I "${here}/logger-host.py" "${eventsFile}"\n`, { mode: 0o755 });
for (const [name, p] of [['com.nextshot.spike', heldWrapper], ['com.nextshot.spike.logger', loggerWrapper]]) {
  fs.writeFileSync(path.join(hostDir, `${name}.json`), JSON.stringify({ name, description: 'N1 spike', path: p, type: 'stdio', allowed_origins: [`chrome-extension://${id}/`] }));
}

const app = spawn(`${bin}/spike-app`, ['com.drewschulz.nextshot.dev.spike-host', `${bin}/spike-host`, '900'], { stdio: ['pipe', 'pipe', 'inherit'] });
const appLines = [];
readline.createInterface({ input: app.stdout }).on('line', (l) => appLines.push({ wall: Date.now(), ...JSON.parse(l) }));
await sleep(800);
fs.writeFileSync(pidFile, String(app.pid));

const started = Date.now();
const chrome = spawn(process.env.CFT_PATH, [
  '--headless=new', `--user-data-dir=${profile}`, `--load-extension=${extDir}`, `--disable-extensions-except=${extDir}`,
  '--no-first-run', '--no-default-browser-check', 'about:blank',
], { stdio: 'ignore' });
console.log(JSON.stringify({ name: 'setup', extensionId: id, chromePid: chrome.pid, note: 'no remote debugging port, no pipe, no automation flag' }));

const readEvents = () => (fs.existsSync(eventsFile) ? fs.readFileSync(eventsFile, 'utf8').trim().split('\n').filter(Boolean).map((l) => JSON.parse(l)) : []);
const waitFor = async (predicate, ms) => { const end = Date.now() + ms; while (Date.now() < end) { const hit = readEvents().find(predicate); if (hit) return hit; await sleep(100); } return null; };

const summary = {};
const hold = await waitFor((e) => e.event === 'hold-opened', 120000);
summary.heldOpenedAtMs = hold ? hold.host_ms - started : null;
const hostSeenWhileHeld = hold ? hostRunning() : 0;
const check = await waitFor((e) => e.event === 'alarm' && e.name === 'hold-check', 150000);
const events = readEvents();
const instances = [...new Set(events.map((e) => e.instance))];
summary.instancesSeen = events.filter((e) => e.event === 'worker-start').map((e) => ({ instance: e.instance, atMs: e.host_ms - started }));
const baseline = events.find((e) => e.event === 'alarm' && e.name === 'baseline-check');
const baselineStarts = events.filter((e) => e.event === 'worker-start' && e.host_ms <= (baseline?.host_ms ?? 0) + 2000);
summary.baselineNoPort = { checkedAtMs: baseline ? baseline.host_ms - started : null, workerStartsBeforeAndAtCheck: baselineStarts.length,
  note: 'a second worker-start at the check means the worker stopped while idle with no port' };
const opener = events.find((e) => e.event === 'hold-opened');
summary.heldPort = { hostProcesses: hostSeenWhileHeld, sameInstanceAtHoldCheck: !!(check && opener && check.instance === opener.instance),
  holdIdleMs: check && hold ? check.host_ms - hold.host_ms : null, openerInstance: opener?.instance, checkInstance: check?.instance };
app.stdin.write('cmd frames\n');
const command = await waitFor((e) => e.event === 'native-message' && e.body?.type === 'command', 5000);
summary.heldPort.commandReachedExtensionAfterIdle = !!command;
summary.heldPort.commandInstance = command?.instance;
console.log(JSON.stringify({ name: 'held-port', ...summary.baselineNoPort ? { baselineNoPort: summary.baselineNoPort } : {}, heldPort: summary.heldPort, workers: summary.instancesSeen }));

// Disconnect by the extension.
const disc = await waitFor((e) => e.event === 'disconnect-called', 30000);
let t = Date.now();
while (hostRunning() && Date.now() - t < 5000) await sleep(10);
console.log(JSON.stringify({ name: 'teardown:extension-disconnect', calledAtMs: disc ? disc.host_ms - started : null, hostGone: !hostRunning(), hostGoneWithinMs: hostRunning() ? null : Date.now() - t,
  appSessionEnded: appLines.filter((e) => e.ev === 'session-ended').map(({ reason }) => reason) }));

// Reload with the port open.
await waitFor((e) => e.event === 'reload-called', 30000);
t = Date.now();
const before = hostRunning();
while (hostRunning() && Date.now() - t < 8000) await sleep(10);
await sleep(1500);
const after = readEvents();
console.log(JSON.stringify({ name: 'teardown:extension-reload', hostsBefore: before, hostGone: !hostRunning(), hostGoneWithinMs: hostRunning() ? null : Date.now() - t,
  appSessionEnded: appLines.filter((e) => e.ev === 'session-ended').map(({ reason }) => reason),
  workerStartsAfterReload: after.filter((e) => e.event === 'worker-start').length - summary.instancesSeen.length }));

// Browser killed while a port is held: reconnect is not scripted after reload, so use the hold-open from a second profile run is not needed;
// the Python fixture covers a killed browser. Stop everything.
chrome.kill('SIGKILL');
app.kill('SIGKILL');
spawnSync('pkill', ['-9', '-f', profile]);
fs.writeFileSync(path.join(work, 'summary.json'), JSON.stringify({ summary, events: readEvents(), app: appLines }, null, 2));
process.exit(0);
