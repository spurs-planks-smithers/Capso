// Installed-Chrome check with a throwaway extension (regular Chrome, Drew's profile, one click).
// Usage: node run.mjs setup <bin folder> <work folder>   starts the app stand-in and waits for the click
//        node run.mjs cleanup <work folder>              removes the two host manifests, stops the stand-in
// This script never touches Chrome, the Pilot install, or the Dev install. It writes two host manifests
// into Chrome's NativeMessagingHosts folder, named com.nextshot.n1spike*, and removes them in cleanup.
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const hostDir = path.join(os.homedir(), 'Library/Application Support/Google/Chrome/NativeMessagingHosts');
const names = ['com.nextshot.n1spike', 'com.nextshot.n1spike.logger'];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const [mode, a, b] = process.argv.slice(2);

if (mode === 'cleanup') {
  for (const name of names) fs.rmSync(path.join(hostDir, `${name}.json`), { force: true });
  spawnSync('pkill', ['-9', '-x', 'spike-app']);
  spawnSync('pkill', ['-9', '-x', 'spike-host']);
  console.log(JSON.stringify({ cleanup: true, manifestsLeft: names.filter((n) => fs.existsSync(path.join(hostDir, `${n}.json`))) }));
  process.exit(0);
}

const bin = a, work = b;
fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });
const id = spawnSync('node', [path.join(here, 'make-extension.mjs')]).stdout.toString().trim();
const pidFile = path.join(work, 'app.pid'), eventsFile = path.join(work, 'events.jsonl');
const held = path.join(work, 'held.sh'), logger = path.join(work, 'logger.sh');
fs.writeFileSync(held, `#!/bin/bash\nexec "${bin}/spike-host" "$1" "$(cat "${pidFile}")" com.drewschulz.nextshot.dev.spike-app "${bin}/spike-app"\n`, { mode: 0o755 });
fs.writeFileSync(logger, `#!/bin/bash\nexec /usr/bin/python3 -I "${path.join(here, '..', 'chromium', 'logger-host.py')}" "${eventsFile}"\n`, { mode: 0o755 });
fs.mkdirSync(hostDir, { recursive: true });
for (const [name, p] of [[names[0], held], [names[1], logger]]) {
  fs.writeFileSync(path.join(hostDir, `${name}.json`), JSON.stringify({ name, description: 'N1 throwaway', path: p, type: 'stdio', allowed_origins: [`chrome-extension://${id}/`] }));
}
const app = spawn(`${bin}/spike-app`, ['com.drewschulz.nextshot.dev.spike-host', `${bin}/spike-host`, '900'], { stdio: ['pipe', 'pipe', 'inherit'] });
const appLines = [];
readline.createInterface({ input: app.stdout }).on('line', (l) => appLines.push(JSON.parse(l)));
await sleep(800);
fs.writeFileSync(pidFile, String(app.pid));
console.log(JSON.stringify({ ready: true, extensionId: id, extensionFolder: path.join(here, 'ext'), appPid: app.pid }));

const events = () => (fs.existsSync(eventsFile) ? fs.readFileSync(eventsFile, 'utf8').trim().split('\n').filter(Boolean).map((l) => JSON.parse(l)) : []);
const until = async (predicate, ms) => { const end = Date.now() + ms; while (Date.now() < end) { if (events().some(predicate)) return true; await sleep(200); } return false; };

await until((e) => e.event === 'click', 90 * 60 * 1000);
await until((e) => e.event === 'review-open', 30000);
const hostParent = spawnSync('ps', ['-o', 'pid=,ppid=,comm=', '-x']).stdout.toString().split('\n').filter((l) => l.includes('spike-host'));
const parentInfo = hostParent.map((l) => l.trim().split(/\s+/)).map(([pid, ppid]) => ({ pid, ppid, parent: spawnSync('ps', ['-o', 'comm=', '-p', ppid]).stdout.toString().trim() }));
await until((e) => e.event === 'hold-start', 40000);
await until((e) => e.event === 'hold-check', 90000);
await until((e) => e.event === 'disconnect-called', 30000);
const t = Date.now();
while (spawnSync('pgrep', ['-x', 'spike-host']).stdout.toString().trim() && Date.now() - t < 5000) await sleep(10);
const result = { hostProcessParents: parentInfo, hostGoneAfterDisconnectMs: Date.now() - t, events: events(), appEvents: appLines };
fs.writeFileSync(path.join(work, 'result.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result));
process.exit(0);
