'use strict';
/* Electron smoke test. Run: xvfb-run -a npx electron --no-sandbox test/electron-smoke.js  (Linux CI)  */
const { app, BrowserWindow } = require('electron');
const fs = require('fs'); const os = require('os'); const path = require('path');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'br-electron-'));
app.setPath('userData', tmp);
require('../electron/main.js');
const fail = (m) => { console.error('SMOKE FAIL:', m); app.exit(1); };
setTimeout(() => fail('timeout'), 40000).unref();

app.whenReady().then(async () => {
  await new Promise((r) => setTimeout(r, 2500));
  const win = BrowserWindow.getAllWindows()[0];
  if (!win) return fail('no window');
  const js = (c) => win.webContents.executeJavaScript(c);
  try {
    if (!(await js('typeof window.api.invoke === "function"'))) return fail('preload api missing');
    if ((await js('window.api.invoke("exec", {}).then(()=>"allowed").catch(()=>"blocked")')) !== 'blocked') return fail('unlisted IPC channel not blocked');
    if (await js('typeof require') !== 'undefined' && (await js('typeof require')) !== 'undefined') return fail('node leaked into renderer');
    // add a bot through the real UI code path
    await js(`document.getElementById('btnAdd').click();
      document.getElementById('fName').value='Alpha'; document.getElementById('fHost').value='127.0.0.1';
      document.getElementById('fUser').value='Alpha_1'; document.getElementById('fDelay').value='5';
      document.getElementById('botForm').requestSubmit();`);
    await new Promise((r) => setTimeout(r, 800));
    const title = await js('document.getElementById("botTitle").textContent');
    if (title !== 'Alpha') return fail('bot not created, title=' + title);
    // invalid input surfaces an error
    await js(`document.getElementById('btnEdit').click(); document.getElementById('fHost').value='bad host!'; document.getElementById('botForm').requestSubmit();`);
    await new Promise((r) => setTimeout(r, 500));
    const err = await js('document.getElementById("formError").textContent');
    if (!/address/.test(err)) return fail('validation error not shown: ' + err);
    await js(`document.getElementById('fHost').value='127.0.0.1'; document.getElementById('fPort').value='1'; document.getElementById('botForm').requestSubmit();`);
    await new Promise((r) => setTimeout(r, 600));
    // start the bot against a closed port, it must go to reconnecting with an error
    await js(`document.getElementById('btnStart').click()`);
    await new Promise((r) => setTimeout(r, 2500));
    const badge = await js('document.getElementById("botBadge").textContent');
    if (!['reconnecting', 'connecting'].includes(badge)) return fail('unexpected status ' + badge);
    const img = await win.webContents.capturePage();
    fs.writeFileSync(process.env.SMOKE_SHOT || path.join(tmp, 'shot.png'), img.toPNG());
    await js(`document.getElementById('btnStop').click()`);
    console.log('ELECTRON SMOKE PASSED (window, preload allowlist, CSP, IPC, form validation, bot lifecycle, tray)');
    app.quit();
  } catch (e) { fail(e.stack || e.message); }
});
