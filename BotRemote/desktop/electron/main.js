'use strict';
const path = require('path');
const { app, BrowserWindow, Tray, Menu, ipcMain, safeStorage, nativeImage, shell } = require('electron');
const QRCode = require('qrcode');
const { ConfigStore } = require('../services/ConfigStore');
const { BotManager } = require('../bots/BotManager');
const { Agent } = require('../agent/Agent');
const { validateBotConfig, normalizeCloudUrl } = require('../services/validation');

// ---- lightweight Chromium: no GPU process needed for a simple form UI --------------------------
app.disableHardwareAcceleration();
app.commandLine.appendSwitch('disable-background-networking');
app.commandLine.appendSwitch('js-flags', '--max-old-space-size=128');

if (!app.requestSingleInstanceLock()) { app.quit(); }

let win = null; let tray = null; let store; let manager; let agent; let quitting = false;

process.on('uncaughtException', (e) => console.error('[main] uncaught:', e));
process.on('unhandledRejection', (e) => console.error('[main] unhandled rejection:', e));

const send = (channel, data) => { if (win && !win.isDestroyed()) win.webContents.send(channel, data); };
const ok = (data) => ({ ok: true, data });
const bad = (e) => ({ ok: false, error: { code: e.code || 'ERROR', message: e.message || String(e) } });
const handle = (channel, fn) => ipcMain.handle(channel, async (_e, payload) => { try { return ok(await fn(payload)); } catch (e) { return bad(e); } });

function createWindow() {
  if (win && !win.isDestroyed()) { if (win.isMinimized()) win.restore(); win.show(); win.focus(); return; }
  win = new BrowserWindow({
    width: 1080, height: 720, minWidth: 860, minHeight: 560, backgroundColor: '#0b0f14', title: 'Bot Remote',
    autoHideMenuBar: true, show: false,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true, spellcheck: false, backgroundThrottling: true },
  });
  win.removeMenu();
  win.loadFile(path.join(__dirname, '../ui/index.html'));
  win.once('ready-to-show', () => win.show());
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (e) => e.preventDefault());
  // Closing the window DESTROYS the renderer (frees its memory); the agent + bots keep running in the tray.
  win.on('closed', () => { win = null; });
}

function buildTray() {
  const icon = nativeImage.createFromPath(path.join(__dirname, '../assets/tray.png'));
  tray = new Tray(icon);
  tray.setToolTip('Bot Remote');
  const refresh = () => tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'Open Bot Remote', click: createWindow },
    { type: 'separator' },
    { label: `Start all bots`, click: () => manager.startAll() },
    { label: 'Stop all bots', click: () => manager.stopAll() },
    { type: 'separator' },
    { label: `Cloud: ${agent.status().state} | Active bots: ${manager.activeCount()}/5`, enabled: false },
    { label: 'Quit (stops all bots)', click: () => { quitting = true; app.quit(); } },
  ]));
  refresh();
  tray.on('click', createWindow);
  tray.on('right-click', refresh); // menu text is rebuilt on demand: no timers
  return refresh;
}

function codec() {
  return {
    encrypt: (s) => (safeStorage.isEncryptionAvailable() ? 'enc:' + safeStorage.encryptString(s).toString('base64') : 'plain:' + Buffer.from(s).toString('base64')),
    decrypt: (s) => (s.startsWith('enc:') ? safeStorage.decryptString(Buffer.from(s.slice(4), 'base64')) : Buffer.from(s.replace(/^plain:/, ''), 'base64').toString()),
  };
}

function registerIpc() {
  handle('state:get', () => ({
    snapshot: manager.snapshot(), settings: store.settings, cloud: agent.status(),
    packaged: app.isPackaged,
  }));
  handle('bot:save', (cfg) => manager.save(cfg));
  handle('bot:remove', (id) => manager.remove(String(id)));
  handle('bot:start', (id) => manager.start(String(id)));
  handle('bot:stop', (id) => manager.stop(String(id)));
  handle('bots:startAll', () => manager.startAll());
  handle('bots:stopAll', () => manager.stopAll());
  handle('bot:chat', ({ id, message }) => {
    const m = String(message || '').trim();
    if (!m || m.length > 256 || /[\u0000-\u001f\u007f]/.test(m)) throw Object.assign(new Error('Message must be 1-256 printable characters'), { code: 'VALIDATION' });
    return manager.chat(String(id), m);
  });
  handle('bot:logs', ({ id, limit }) => manager.logs(String(id), Math.min(500, Number(limit) || 200)));
  handle('bot:clearLogs', (id) => manager.clearLogs(String(id)));
  handle('settings:set', (patch) => {
    const next = {};
    if (patch && typeof patch.cloudUrl === 'string') next.cloudUrl = patch.cloudUrl.trim() ? normalizeCloudUrl(patch.cloudUrl) : '';
    if (patch && typeof patch.autoConnect === 'boolean') next.autoConnect = patch.autoConnect;
    if (patch && typeof patch.launchAtLogin === 'boolean') {
      next.launchAtLogin = patch.launchAtLogin;
      if (app.isPackaged) app.setLoginItemSettings({ openAtLogin: patch.launchAtLogin, args: ['--hidden'] });
    }
    store.setSettings(next);
    return store.settings;
  });
  handle('cloud:connect', async ({ registrationKey } = {}) => { await agent.connect({ registrationKey: registrationKey ? String(registrationKey) : undefined }); return agent.status(); });
  handle('cloud:disconnect', () => { agent.disconnect(); return agent.status(); });
  handle('cloud:reset', () => { agent.resetRegistration(); return agent.status(); });
  handle('pair:create', async () => {
    const { payload, expiresAt } = await agent.createPairing();
    const text = JSON.stringify(payload);
    const qr = await QRCode.toDataURL(text, { margin: 1, width: 300, errorCorrectionLevel: 'M', color: { dark: '#000000', light: '#ffffff' } });
    return { qr, text, expiresAt };
  });
  handle('phones:list', () => agent.listPhones());
  handle('phones:revoke', (id) => agent.revokePhone(String(id)));
}

function wireEvents(refreshTray) {
  manager.on('snapshot', (s) => send('evt:snapshot', s));
  manager.on('status', (b) => { send('evt:status', b); });
  manager.on('log', (botId, entry) => send('evt:log', { botId, entry }));
  manager.on('chat', (botId, entry) => send('evt:log', { botId, entry }));
  agent.on('state', (s) => { send('evt:cloud', s); refreshTray(); });
  agent.on('phones-changed', () => send('evt:phones'));
  agent.on('paired', (p) => send('evt:paired', p));
}

app.on('second-instance', createWindow);
app.on('window-all-closed', () => { /* keep running in the system tray */ });
app.on('before-quit', () => { quitting = true; });
app.on('will-quit', () => { try { agent && agent.disconnect(false); manager && manager.dispose(); } catch (e) { console.error(e); } });
['SIGINT', 'SIGTERM'].forEach((sig) => process.on(sig, () => app.quit()));

app.whenReady().then(() => {
  const dir = app.getPath('userData');
  store = new ConfigStore(dir, codec());
  manager = new BotManager({ store, profilesDir: path.join(dir, 'auth-cache') });
  agent = new Agent({ store, manager, deviceName: require('os').hostname() });
  registerIpc();
  const refreshTray = buildTray();
  wireEvents(refreshTray);
  if (store.settings.autoConnect && store.settings.cloudUrl) agent.connect().catch((e) => console.warn('[agent] auto-connect failed:', e.message));
  if (!process.argv.includes('--hidden')) createWindow();
});
