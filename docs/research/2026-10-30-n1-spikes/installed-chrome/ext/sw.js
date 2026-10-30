// Throwaway installed-Chrome probe. One toolbar click runs the whole sequence once.
// Every step logs through a one-shot native host, so the result reaches the test script
// without a debugger. Page pixels are measured by length only and discarded.
const instance = Math.random().toString(36).slice(2, 8);
const LOGGER = 'com.nextshot.n1spike.logger';
const HELD = 'com.nextshot.n1spike';
let port = null;
let step = 'idle';
let chunks = 0;
let chunkBytes = 0;

const log = (event, extra = {}) => new Promise((resolve) => {
  chrome.runtime.sendNativeMessage(LOGGER, { event, instance, ...extra }, () => { void chrome.runtime.lastError; resolve(); });
});
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const waitType = (type, ms) => new Promise((resolve) => {
  const started = Date.now();
  const timer = setInterval(() => {
    if (waiting[type] || Date.now() - started > ms) { clearInterval(timer); resolve(waiting[type] ?? null); }
  }, 20);
});
const waiting = {};
log('worker-start');

function open() {
  for (const key of Object.keys(waiting)) delete waiting[key];
  port = chrome.runtime.connectNative(HELD);
  port.onMessage.addListener((body) => {
    waiting[body.type] = body;
    if (body.type === 'chunk') { chunks += 1; chunkBytes += body.data.length; }
  });
  port.onDisconnect.addListener(() => { log('native-disconnect', { step, error: chrome.runtime.lastError?.message ?? null }); port = null; });
}

chrome.action.onClicked.addListener(async (tab) => {
  await log('click', { tabUrl: tab.url ?? null, note: 'real toolbar gesture' });
  // 1. Did the real gesture grant activeTab? Compare the fixture, where a plain message failed.
  try { const image = await chrome.tabs.captureVisibleTab(); await log('capture-after-click', { ok: true, bytes: image.length }); }
  catch (error) { await log('capture-after-click', { ok: false, error: String(error) }); }
  try {
    const [{ result }] = await chrome.scripting.executeScript({ target: { tabId: tab.id }, func: () => document.title });
    await log('script-after-click', { ok: true, title: result });
  } catch (error) { await log('script-after-click', { ok: false, error: String(error) }); }

  // 2. Held native port, Apple Event to the app (consent with a Chrome parent).
  step = 'open'; open(); port.postMessage({ op: 'open' });
  const ready = await waitType('ready', 8000) ?? await waitType('closed', 100);
  await log('review-open', { reply: ready });
  if (!ready || ready.type !== 'ready') { chrome.action.setBadgeText({ text: 'ERR' }); return; }

  // 3. Message size. Chunks of 512 KB: expect success. Extension to host 2 MB: expect success.
  step = 'chunks-512k'; chunks = 0; chunkBytes = 0; const began = Date.now();
  port.postMessage({ op: 'burst', bytes: 5 * 1024 * 1024, chunk: 512 * 1024 });
  const done = await waitType('burst-done', 15000);
  await log('burst-512k', { done: !!done, chunks, chunkBytes, ms: Date.now() - began });
  step = 'echo-2mb'; delete waiting.echo;
  port.postMessage({ op: 'echo', data: 'B'.repeat(2 * 1024 * 1024) });
  await log('echo-2mb', { reply: await waitType('echo', 8000) });

  // 4. Idle hold with the port open and no events. An alarm wakes the check.
  step = 'hold'; await log('hold-start');
  chrome.alarms.create('hold-check', { when: Date.now() + 45000 });
});

chrome.alarms.onAlarm.addListener(async ({ name }) => {
  if (name === 'hold-check') {
    await log('hold-check', { portStillOpen: !!port, note: 'same instance as click means the worker stayed alive' });
    // 5. Oversize frame from the host: 1.2 MB. Chrome should close the port.
    step = 'oversize-1.2mb';
    if (port) port.postMessage({ op: 'burst', bytes: 1200000, chunk: 1200000 });
    await sleep(3000);
    await log('oversize-result', { portStillOpen: !!port });
    if (port) { step = 'close'; port.disconnect(); await log('disconnect-called'); }
    chrome.action.setBadgeText({ text: 'DONE' });
  }
});
