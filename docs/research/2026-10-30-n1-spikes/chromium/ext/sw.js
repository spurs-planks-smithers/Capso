// Records every start of this worker and every native port event in storage.session.
// It never sets a timer or heartbeat, so only a native port can keep it alive.
let port = null;
async function note(kind, extra) {
  const { log = [] } = await chrome.storage.session.get('log');
  log.push({ kind, at: Date.now(), ...extra });
  await chrome.storage.session.set({ log });
}
note('worker-start');
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  (async () => {
    if (message.op === 'connect') {
      try {
        port = chrome.runtime.connectNative(message.name);
        port.onMessage.addListener((body) => note('native-message', { body }));
        port.onDisconnect.addListener(() => note('native-disconnect', { error: chrome.runtime.lastError?.message ?? null }));
        await note('connect-called', { name: message.name });
      } catch (error) { await note('connect-threw', { error: String(error) }); }
    } else if (message.op === 'post') {
      port?.postMessage(message.body);
    } else if (message.op === 'disconnect') {
      port?.disconnect(); await note('disconnect-called');
    } else if (message.op === 'capture') {
      try { const url = await chrome.tabs.captureVisibleTab(); await note('capture-ok', { bytes: url.length }); }
      catch (error) { await note('capture-failed', { error: String(error) }); }
    } else if (message.op === 'script') {
      try {
        const [{ result }] = await chrome.scripting.executeScript({ target: { tabId: message.tabId }, func: () => document.title });
        await note('script-ok', { url: message.url, result });
      } catch (error) { await note('script-failed', { url: message.url, error: String(error) }); }
    } else if (message.op === 'reload') {
      await note('reload-called'); chrome.runtime.reload();
    }
    respond({ ok: true });
  })();
  return true;
});
