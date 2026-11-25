'use strict';
/* Renderer: plain DOM, no framework. All dynamic text is set via textContent (no innerHTML with data). */
const $ = (id) => document.getElementById(id);
const MAX_LOG_NODES = 500;
const state = { bots: new Map(), selected: null, settings: {}, cloud: {}, view: 'empty', uptimeTimer: null, qrTimer: null };

async function call(channel, payload) {
  const r = await window.api.invoke(channel, payload);
  if (!r.ok) throw new Error(r.error.message);
  return r.data;
}
function toast(msg) {
  const t = $('toast'); t.textContent = msg; t.classList.remove('hidden');
  clearTimeout(toast.h); toast.h = setTimeout(() => t.classList.add('hidden'), 3500);
}
const guard = (fn) => async (...a) => { try { await fn(...a); } catch (e) { toast(e.message); } };
const fmtTime = (t) => new Date(t).toLocaleTimeString([], { hour12: false });
const fmtUptime = (ms) => { const s = Math.floor(ms / 1000); const h = Math.floor(s / 3600); const m = Math.floor((s % 3600) / 60); return `${h}h ${String(m).padStart(2, '0')}m ${String(s % 60).padStart(2, '0')}s`; };

function show(view) {
  state.view = view;
  for (const v of ['Empty', 'Bot', 'Form', 'Cloud']) $('view' + v).classList.toggle('hidden', v.toLowerCase() !== view);
  if (view !== 'bot') stopUptime();
}

// ---- sidebar ---------------------------------------------------------------------------------
function renderList() {
  const ul = $('botList'); ul.textContent = '';
  let active = 0;
  for (const b of state.bots.values()) {
    if (b.status !== 'stopped') active++;
    const li = document.createElement('li');
    if (b.id === state.selected && state.view === 'bot') li.classList.add('sel');
    const dot = document.createElement('span'); dot.className = 'dot ' + b.status;
    const box = document.createElement('div');
    const name = document.createElement('div'); name.textContent = b.name;
    const sub = document.createElement('small'); sub.textContent = `${b.host}:${b.port} · ${b.status}`;
    box.append(name, sub); li.append(dot, box);
    li.addEventListener('click', () => selectBot(b.id));
    ul.appendChild(li);
  }
  $('capText').textContent = `${active} / 5 active`;
  $('capBar').style.width = (active / 5) * 100 + '%';
}

async function selectBot(id) {
  state.selected = id; show('bot'); renderBot(); renderList();
  const logs = await call('bot:logs', { id, limit: 300 });
  const box = $('logBox'); box.textContent = '';
  logs.forEach(addLogLine);
}

function renderBot() {
  const b = state.bots.get(state.selected);
  if (!b) { show('empty'); return; }
  $('botTitle').textContent = b.name;
  $('botBadge').textContent = b.status; $('botBadge').className = 'badge ' + b.status;
  $('botInfo').textContent = `${b.username} @ ${b.host}:${b.port} · ${b.auth}${b.serverVersion ? ' · ' + b.serverVersion : ''}`;
  $('btnStart').disabled = b.status !== 'stopped';
  $('btnStop').disabled = b.status === 'stopped';
  $('btnEdit').disabled = b.status !== 'stopped';
  $('btnSend').disabled = $('chatInput').disabled = b.status !== 'online';
  const err = $('botError');
  if (b.lastError && b.status !== 'online') { err.textContent = b.lastError; err.classList.remove('hidden'); } else err.classList.add('hidden');
  if (b.status === 'online') startUptime(); else { stopUptime(); $('botUptime').textContent = ''; }
}
function startUptime() {
  stopUptime();
  const tick = () => { const b = state.bots.get(state.selected); $('botUptime').textContent = b && b.connectedAt ? '· uptime ' + fmtUptime(Date.now() - b.connectedAt) : ''; };
  tick(); state.uptimeTimer = setInterval(tick, 1000);   // only runs while an online bot is displayed
}
function stopUptime() { if (state.uptimeTimer) { clearInterval(state.uptimeTimer); state.uptimeTimer = null; } }

function addLogLine(e) {
  const box = $('logBox');
  const stick = box.scrollTop + box.clientHeight >= box.scrollHeight - 30;
  const d = document.createElement('div'); d.className = e.k;
  const ts = document.createElement('span'); ts.className = 'ts'; ts.textContent = fmtTime(e.t);
  d.append(ts, document.createTextNode(e.m));
  box.appendChild(d);
  while (box.childNodes.length > MAX_LOG_NODES) box.removeChild(box.firstChild);
  if (stick) box.scrollTop = box.scrollHeight;
}

// ---- form ------------------------------------------------------------------------------------
function openForm(bot) {
  show('form'); $('formError').classList.add('hidden');
  $('formTitle').textContent = bot ? 'Edit bot' : 'Add bot';
  $('fId').value = bot ? bot.id : '';
  $('fName').value = bot ? bot.name : ''; $('fHost').value = bot ? bot.host : '';
  $('fPort').value = bot ? bot.port : 25565; $('fAuth').value = bot ? bot.auth : 'offline';
  $('fUser').value = bot ? bot.username : ''; $('fVersion').value = bot ? bot.version : '';
  $('fDelay').value = bot ? bot.reconnectDelaySec : 10; $('fReconnect').checked = bot ? bot.autoReconnect : true;
  $('btnDelete').classList.toggle('hidden', !bot);
  syncAuth(); renderList();
}
function syncAuth() {
  const ms = $('fAuth').value === 'microsoft';
  $('fUserLabel').textContent = ms ? 'Microsoft account label (e.g. e-mail)' : 'Username';
  $('msaHint').classList.toggle('hidden', !ms);
}

// ---- cloud view ------------------------------------------------------------------------------
function renderCloud() {
  const c = state.cloud;
  $('cloudBadge').textContent = c.state || 'disconnected'; $('cloudBadge').className = 'badge ' + (c.state || '');
  $('cloudMsg').textContent = c.error || (c.state === 'connected' ? `${c.phonesOnline || 0} phone(s) online` : '');
  $('cloudDot').className = 'dot ' + (c.state || '');
  $('btnPair').disabled = c.state !== 'connected';
}
async function renderPhones() {
  const ul = $('phoneList'); ul.textContent = '';
  if (state.cloud.state !== 'connected') { const li = document.createElement('li'); li.textContent = 'Connect to the cloud to manage devices.'; li.className = 'muted'; ul.appendChild(li); return; }
  let phones = [];
  try { phones = await call('phones:list'); } catch (e) { toast(e.message); }
  if (!phones.length) { const li = document.createElement('li'); li.textContent = 'No paired devices yet.'; li.className = 'muted'; ul.appendChild(li); return; }
  for (const p of phones) {
    const li = document.createElement('li');
    const dot = document.createElement('span'); dot.className = 'dot ' + (p.online ? 'online' : '');
    const name = document.createElement('span'); name.textContent = `${p.name} · paired ${new Date(p.createdAt).toLocaleDateString()}`;
    const sp = document.createElement('span'); sp.className = 'spacer';
    const rv = document.createElement('button'); rv.className = 'btn small danger'; rv.textContent = 'Revoke';
    rv.addEventListener('click', guard(async () => { await call('phones:revoke', p.id); toast('Device revoked'); renderPhones(); }));
    li.append(dot, name, sp, rv); ul.appendChild(li);
  }
}
function openCloud() {
  show('cloud'); $('cUrl').value = state.settings.cloudUrl || '';
  $('cAuto').checked = state.settings.autoConnect !== false; $('cLogin').checked = !!state.settings.launchAtLogin;
  renderCloud(); renderPhones(); renderList();
}
function hideQr() { $('qrBox').classList.add('hidden'); $('qrImg').removeAttribute('src'); $('qrText').value = ''; clearTimeout(state.qrTimer); }

// ---- events ----------------------------------------------------------------------------------
$('btnAdd').onclick = () => openForm(null);
$('btnCloud').onclick = openCloud;
$('btnCancel').onclick = () => (state.selected && state.bots.has(state.selected) ? selectBot(state.selected) : (show('empty'), renderList()));
$('btnEdit').onclick = () => openForm(state.bots.get(state.selected));
$('fAuth').onchange = syncAuth;
$('btnStart').onclick = guard(() => call('bot:start', state.selected));
$('btnStop').onclick = guard(() => call('bot:stop', state.selected));
$('btnStartAll').onclick = guard(async () => { const r = await call('bots:startAll'); if (r.skipped.length) toast(`${r.skipped.length} bot(s) not started (limit or duplicate account)`); });
$('btnStopAll').onclick = guard(() => call('bots:stopAll'));
$('btnClear').onclick = guard(async () => { await call('bot:clearLogs', state.selected); $('logBox').textContent = ''; });
$('btnDelete').onclick = guard(async () => {
  if (!confirm('Delete this bot?')) return;
  const id = $('fId').value; await call('bot:remove', id);
  if (state.selected === id) state.selected = null; show('empty'); renderList();
});
const sendChat = guard(async () => {
  const input = $('chatInput'); const message = input.value.trim(); if (!message) return;
  await call('bot:chat', { id: state.selected, message }); input.value = '';
});
$('btnSend').onclick = sendChat;
$('chatInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') sendChat(); });

$('botForm').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  try {
    const saved = await call('bot:save', {
      id: $('fId').value || undefined, name: $('fName').value, host: $('fHost').value, port: Number($('fPort').value),
      auth: $('fAuth').value, username: $('fUser').value, version: $('fVersion').value,
      reconnectDelaySec: Number($('fDelay').value), autoReconnect: $('fReconnect').checked,
    });
    state.bots.set(saved.id, saved); await selectBot(saved.id);
  } catch (e) { const el = $('formError'); el.textContent = e.message; el.classList.remove('hidden'); }
});

$('btnConnect').onclick = guard(async () => {
  await call('settings:set', { cloudUrl: $('cUrl').value, autoConnect: $('cAuto').checked, launchAtLogin: $('cLogin').checked });
  state.settings = (await call('state:get')).settings;
  await call('cloud:connect', { registrationKey: $('cKey').value }); $('cKey').value = '';
});
$('btnDisconnect').onclick = guard(() => call('cloud:disconnect'));
$('btnReset').onclick = guard(async () => { if (confirm('Forget this PC on the cloud? All paired phones will stop working.')) { await call('cloud:reset'); hideQr(); toast('Registration reset'); } });
$('cAuto').onchange = guard(() => call('settings:set', { autoConnect: $('cAuto').checked }));
$('cLogin').onchange = guard(() => call('settings:set', { launchAtLogin: $('cLogin').checked }));
$('btnPair').onclick = guard(async () => {
  const r = await call('pair:create');
  $('qrText').value = r.text; $('qrImg').src = r.qr; $('qrBox').classList.remove('hidden');
  $('qrInfo').textContent = `Single-use. Expires at ${fmtTime(r.expiresAt)}.`;
  clearTimeout(state.qrTimer); state.qrTimer = setTimeout(hideQr, Math.max(0, r.expiresAt - Date.now()));
});

window.api.on('evt:snapshot', (s) => { state.bots = new Map(s.bots.map((b) => [b.id, b])); if (state.selected && !state.bots.has(state.selected)) { state.selected = null; if (state.view === 'bot') show('empty'); } renderList(); if (state.view === 'bot') renderBot(); });
window.api.on('evt:status', (b) => { state.bots.set(b.id, b); renderList(); if (state.view === 'bot' && b.id === state.selected) renderBot(); });
window.api.on('evt:log', ({ botId, entry }) => { if (state.view === 'bot' && botId === state.selected) addLogLine(entry); });
window.api.on('evt:cloud', (c) => { state.cloud = c; renderCloud(); if (state.view === 'cloud') renderPhones(); });
window.api.on('evt:phones', () => { if (state.view === 'cloud') renderPhones(); });
window.api.on('evt:paired', (p) => { toast(`Paired: ${p.name}`); hideQr(); });

(async () => {
  const s = await call('state:get');
  state.bots = new Map(s.snapshot.bots.map((b) => [b.id, b]));
  state.settings = s.settings; state.cloud = s.cloud;
  renderList(); renderCloud();
  if (!state.settings.cloudUrl) openCloud(); else if (state.bots.size) selectBot(state.bots.values().next().value.id);
})();
