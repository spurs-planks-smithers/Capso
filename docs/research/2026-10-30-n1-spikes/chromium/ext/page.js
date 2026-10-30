window.call = (message) => chrome.runtime.sendMessage(message);
window.readLog = async () => (await chrome.storage.session.get('log')).log ?? [];
