// Self-driven lifecycle probe. No debugger or page script touches this worker, so Chrome's
// own 30 second idle rule applies. Alarms wake the worker at fixed times. Every wake and every
// native event is logged through a one-shot native host with a per-worker instance id.
const instance = Math.random().toString(36).slice(2, 8);
const LOGGER = 'com.nextshot.spike.logger';
const HELD = 'com.nextshot.spike';
let port = null;

function log(event, extra = {}) {
  chrome.runtime.sendNativeMessage(LOGGER, { event, instance, ...extra }, () => void chrome.runtime.lastError);
}
log('worker-start');

function hold() {
  port = chrome.runtime.connectNative(HELD);
  port.onMessage.addListener((body) => log('native-message', { body }));
  port.onDisconnect.addListener(() => log('native-disconnect', { error: chrome.runtime.lastError?.message ?? null }));
  port.postMessage({ op: 'open' });
  log('hold-opened');
}

// Delays in ms after install. The long gaps have no event, so the 30 second idle rule can act.
const PLAN = [
  ['baseline-check', 45000],   // no port open since start: did the worker stop and restart?
  ['hold-open', 50000],        // open the held native port
  ['hold-check', 140000],      // 90 s later with the port open: same worker instance?
  ['hold-disconnect', 150000], // extension closes the port
  ['reload-open', 155000],     // open again, then
  ['reload-now', 158000],      // reload the extension while the port is open
];

chrome.runtime.onInstalled.addListener(({ reason }) => {
  log('installed', { reason });
  if (reason !== 'install') return;
  for (const [name, delay] of PLAN) chrome.alarms.create(name, { when: Date.now() + delay });
});

chrome.alarms.onAlarm.addListener(({ name }) => {
  log('alarm', { name });
  if (name === 'hold-open' || name === 'reload-open') hold();
  if (name === 'hold-disconnect') { port?.disconnect(); log('disconnect-called'); }
  if (name === 'reload-now') { log('reload-called'); setTimeout(() => chrome.runtime.reload(), 100); }
});
