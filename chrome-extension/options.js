const DEFAULT_API_BASE = 'http://127.0.0.1:3000';

document.addEventListener('DOMContentLoaded', () => {
  chrome.storage.sync.get({ apiBase: DEFAULT_API_BASE, apiKey: '' }, (items) => {
    document.getElementById('apiBase').value = items.apiBase;
    document.getElementById('apiKey').value = items.apiKey;
  });

  document.getElementById('save').addEventListener('click', () => {
    const apiBase = document.getElementById('apiBase').value.trim() || DEFAULT_API_BASE;
    const apiKey = document.getElementById('apiKey').value.trim();
    chrome.storage.sync.set({ apiBase, apiKey }, () => {
      const saved = document.getElementById('saved');
      saved.hidden = false;
      setTimeout(() => {
        saved.hidden = true;
      }, 2000);
    });
  });

  document.getElementById('test').addEventListener('click', async () => {
    const status = document.getElementById('testStatus');
    status.className = 'hint';
    status.textContent = 'Testing…';

    const apiBase = document.getElementById('apiBase').value.trim() || DEFAULT_API_BASE;
    const apiKey = document.getElementById('apiKey').value.trim();
    await new Promise((resolve) => chrome.storage.sync.set({ apiBase, apiKey }, resolve));

    chrome.runtime.sendMessage({ type: 'TEST_CONNECTION' }, (response) => {
      if (chrome.runtime.lastError) {
        status.className = 'error';
        status.textContent = chrome.runtime.lastError.message;
        return;
      }
      if (response?.ok) {
        status.className = 'ok';
        status.textContent = 'Connected — API key is valid.';
      } else {
        status.className = 'error';
        status.textContent = response?.error || 'Connection failed';
      }
    });
  });
});
