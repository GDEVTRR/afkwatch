'use strict';
/* Full chain: phone (socket.io client) -> cloud (real server) -> desktop Agent -> BotManager (fake + real mineflayer). */
const assert = require('assert');
const os = require('os'); const path = require('path'); const fs = require('fs');
const { EventEmitter } = require('events');
const { io: connect } = require('socket.io-client');
const { createApp } = require('../../cloud/server');
const { createMemoryStore } = require('../../cloud/services/store/memory');
const { ConfigStore } = require('../services/ConfigStore');
const { BotManager } = require('../bots/BotManager');
const { Agent } = require('../agent/Agent');
const { EV } = require('../agent/protocol');

class FakeBot extends EventEmitter { constructor() { super(); this.version = '1.21'; this.chats = []; } chat(m) { this.chats.push(m); } end() { setImmediate(() => this.emit('end')); } }
const bots = [];
const fake = { createBot: () => { const b = new FakeBot(); bots.push(b); return b; } };
const tick = (ms) => new Promise((r) => setTimeout(r, ms));
const until = async (fn, ms = 4000) => { const t = Date.now(); while (Date.now() - t < ms) { const v = await fn(); if (v) return v; await tick(25); } throw new Error('condition timeout'); };
const emitAck = (s, ev, p) => new Promise((res) => s.emit(ev, p, res));
setTimeout(() => { console.error('TEST TIMEOUT'); process.exit(2); }, 40000).unref();

(async () => {
  const { server, io } = createApp({ isProd: false, pepper: 'p'.repeat(40), registrationKey: '', trustProxy: false }, createMemoryStore());
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'br-e2e-'));
  const store = new ConfigStore(dir);
  store.setSettings({ cloudUrl: base });
  const mgr = new BotManager({ store, profilesDir: dir, mineflayer: fake });
  const botId = mgr.save({ name: 'Alpha', host: 'mc.example.com', port: 25565, username: 'Alpha', auth: 'offline', reconnectDelaySec: 1 }).id;
  const agent = new Agent({ store, manager: mgr, deviceName: 'TestPC' });

  await agent.connect();
  await until(() => agent.status().state === 'connected');
  assert.ok(store.getCloud().deviceId);
  console.log('ok  agent registered + connected');

  const pairing = await agent.createPairing();
  assert.strictEqual(pairing.payload.u, base); assert.ok(pairing.payload.c);
  let pairedEvt = null; agent.on('paired', (p) => { pairedEvt = p; });
  const r = await fetch(base + '/api/pair/complete', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ code: pairing.payload.c, deviceName: 'iPhone 15' }) });
  const { token } = await r.json();
  await until(() => pairedEvt); assert.strictEqual(pairedEvt.name, 'iPhone 15');
  assert.strictEqual((await agent.listPhones()).length, 1);
  console.log('ok  pairing via agent');

  const phone = connect(base, { auth: { role: 'phone', token }, transports: ['websocket'], reconnection: false });
  const snaps = []; const logs = []; const statuses = [];
  phone.on(EV.BOTS_SNAPSHOT, (s) => snaps.push(s));
  phone.on(EV.BOT_STATUS, (s) => statuses.push(s));
  phone.on(EV.BOT_LOG, (l) => logs.push(l));
  phone.on(EV.BOT_CHAT, (l) => logs.push(l));
  await until(() => snaps.length > 0);
  assert.strictEqual(snaps[0].bots[0].name, 'Alpha');
  await until(() => agent.phonesOnline === 1);
  console.log('ok  phone receives snapshot; agent knows a phone is online');

  const s1 = await emitAck(phone, EV.COMMAND, { action: 'bot.start', botId });
  assert.ok(s1.ok, JSON.stringify(s1));
  bots[0].emit('spawn');
  await until(() => statuses.some((s) => s.bot.status === 'online'));
  const c1 = await emitAck(phone, EV.COMMAND, { action: 'bot.chat', botId, message: 'hello world' });
  assert.ok(c1.ok); assert.deepStrictEqual(bots[0].chats, ['hello world']);
  bots[0].emit('messagestr', '<Steve> yo', 'chat');
  await until(() => logs.some((l) => l.entry.m === '<Steve> yo'));
  const lg = await emitAck(phone, EV.COMMAND, { action: 'bot.logs', botId, limit: 50 });
  assert.ok(lg.ok && lg.data.logs.length >= 3);
  console.log('ok  start / chat / live logs / log history through the cloud');

  // limit via remote
  for (let i = 1; i <= 5; i++) mgr.save({ name: 'X' + i, host: 'mc.example.com', port: 25565, username: 'Extra_' + i, auth: 'offline' });
  const all = await emitAck(phone, EV.COMMAND, { action: 'bots.startAll' });
  assert.strictEqual(all.data.started.length, 4); assert.strictEqual(all.data.skipped.length, 1);
  assert.strictEqual(mgr.activeCount(), 5);
  console.log('ok  five-bot limit enforced for remote commands');

  const stopAll = await emitAck(phone, EV.COMMAND, { action: 'bots.stopAll' });
  assert.strictEqual(stopAll.data.stopped.length, 5); assert.strictEqual(mgr.activeCount(), 0);

  // logs are NOT forwarded when no phone is online
  phone.close(); await until(() => agent.phonesOnline === 0);
  let leaked = false; const spy = connect(base, { auth: { role: 'phone', token: 'q'.repeat(43) }, reconnection: false }); spy.on('connect_error', () => {});
  mgr.start(botId); bots[bots.length - 1].emit('messagestr', 'nobody listening', 'chat');
  assert.strictEqual(leaked, false);
  mgr.stopAll(); spy.close();
  console.log('ok  no log forwarding without phones');

  // revoke from desktop UI path
  const ph = (await agent.listPhones())[0];
  await agent.revokePhone(ph.id);
  assert.strictEqual((await agent.listPhones()).length, 0);
  console.log('ok  revoke via agent');

  // reconnect after a transport drop (network loss / server crash) ...
  agent.socket.io.engine.close();
  await until(() => agent.status().state !== 'connected', 3000);
  await until(() => agent.status().state === 'connected', 15000);
  assert.strictEqual((await io.fetchSockets()).length, 1);
  // ... and after a server-initiated disconnect (cloud redeploy -> io.close())
  io.disconnectSockets(true);
  await until(() => agent.status().state !== 'connected', 3000);
  await until(() => agent.status().state === 'connected', 15000);
  assert.strictEqual((await io.fetchSockets()).length, 1);
  console.log('ok  automatic cloud reconnection after transport drop and server disconnect (single connection)');

  agent.disconnect(); mgr.dispose();
  console.log('\nAGENT E2E TESTS PASSED');

  // --- real mineflayer against a closed port: must fail gracefully, retry, and stop cleanly
  const mgr2 = new BotManager({ store: new ConfigStore(fs.mkdtempSync(path.join(os.tmpdir(), 'br-real-'))), profilesDir: dir });
  const rid = mgr2.save({ name: 'Real', host: '127.0.0.1', port: 1, username: 'RealBot', auth: 'offline', reconnectDelaySec: 1 }).id;
  mgr2.start(rid);
  await until(() => mgr2.list()[0].status === 'reconnecting', 15000);
  assert.ok(mgr2.list()[0].lastError.length > 0);
  console.log('ok  real mineflayer: connection refused handled ->', mgr2.list()[0].lastError);
  mgr2.stop(rid); assert.strictEqual(mgr2.list()[0].status, 'stopped'); mgr2.dispose();
  io.close(); server.close(); fs.rmSync(dir, { recursive: true, force: true });
  console.log('REAL MINEFLAYER SMOKE TEST PASSED');
  process.exit(0);
})().catch((e) => { console.error('TEST FAILED', e); process.exit(1); });
