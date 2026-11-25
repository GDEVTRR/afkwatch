'use strict';
/* End-to-end test: real HTTP + Socket.IO against an ephemeral server with the in-memory store. */
const assert = require('assert');
const { io: connect } = require('socket.io-client');
const { createApp } = require('../server');
const { createMemoryStore } = require('../services/store/memory');
const { EV } = require('../services/protocol');

const once = (s, ev) => new Promise((res) => s.once(ev, res));
const emitAck = (s, ev, p) => new Promise((res) => s.emit(ev, p, res));
const post = async (base, path, body, headers = {}) => {
  const r = await fetch(base + path, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) });
  return { status: r.status, body: await r.json() };
};
const expectConnectError = (url, auth) => new Promise((res, rej) => {
  const s = connect(url, { auth, transports: ['websocket'], reconnection: false });
  s.on('connect', () => { s.close(); rej(new Error('should not connect')); });
  s.on('connect_error', (e) => { s.close(); res(e.message); });
});

setTimeout(() => { console.error('TEST TIMEOUT'); process.exit(2); }, 25000).unref();
(async () => {
  const store = createMemoryStore();
  const cfg = { isProd: false, port: 0, pepper: 'x'.repeat(40), registrationKey: 'sekret', trustProxy: false };
  const { server, io } = createApp(cfg, store);
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const cleanup = [];

  // registration requires key
  assert.strictEqual((await post(base, '/api/desktop/register', { name: 'PC' })).status, 403);
  const reg = await post(base, '/api/desktop/register', { name: 'PC', registrationKey: 'sekret' });
  assert.strictEqual(reg.status, 201);
  const { deviceId, token } = reg.body;
  console.log('ok  registration (key enforced)');

  // bad auth rejected
  assert.strictEqual(await expectConnectError(base, { role: 'desktop', deviceId, token: 'y'.repeat(43) }), 'unauthorized');
  assert.strictEqual(await expectConnectError(base, { role: 'phone', token: 'z'.repeat(43) }), 'unauthorized');
  assert.strictEqual(await expectConnectError(base, {}), 'unauthorized');
  console.log('ok  unauthenticated sockets rejected');

  // desktop connects, creates pairing code
  const desk = connect(base, { auth: { role: 'desktop', deviceId, token }, transports: ['websocket'], reconnection: false });
  cleanup.push(desk);
  const p0 = await once(desk, EV.PRESENCE);
  assert.strictEqual(p0.phonesOnline, 0);
  const pc = await emitAck(desk, EV.D_PAIRING_CREATE, {});
  assert.ok(pc.ok && pc.data.code && pc.data.expiresAt > Date.now() + 290000 && pc.data.expiresAt <= Date.now() + 300000);
  console.log('ok  desktop authenticated, pairing code issued (5 min TTL)');

  // expired codes are rejected
  await store.replacePairing(deviceId, require('crypto').createHmac('sha256', cfg.pepper).update('E'.repeat(32)).digest('hex'), Date.now() - 1000);
  assert.strictEqual((await post(base, '/api/pair/complete', { code: 'E'.repeat(32), deviceName: 'x' })).status, 400);
  const pc2 = await emitAck(desk, EV.D_PAIRING_CREATE, {});

  // pairing: single use
  const paired = once(desk, EV.PAIRING_COMPLETED);
  const done = await post(base, '/api/pair/complete', { code: pc2.data.code, deviceName: 'Test iPhone' });
  assert.strictEqual(done.status, 201);
  assert.ok(done.body.token && done.body.phoneId && !('desktopId' in done.body) && !JSON.stringify(done.body).includes(token));
  assert.strictEqual((await paired).name, 'Test iPhone');
  assert.strictEqual((await post(base, '/api/pair/complete', { code: pc2.data.code, deviceName: 'again' })).status, 400);
  assert.strictEqual((await post(base, '/api/pair/complete', { code: 'short' })).status, 400);
  console.log('ok  pairing single-use, expiry, no desktop credential leaked');

  // desktop streams state before phone joins -> phone receives cached snapshot
  const bot = { id: 'b1', name: 'Alpha', host: 'mc.example.com', port: 25565, username: 'Alpha', auth: 'offline', version: '', autoReconnect: true, reconnectDelaySec: 10, status: 'stopped', connectedAt: null, serverVersion: '', lastError: '' };
  desk.emit(EV.BOTS_SNAPSHOT, { bots: [bot, { id: 'bad id!' }, 'junk'] });
  await new Promise((r) => setTimeout(r, 100));

  const phone = connect(base, { auth: { role: 'phone', token: done.body.token }, transports: ['websocket'], reconnection: false });
  cleanup.push(phone);
  const snapP = once(phone, EV.BOTS_SNAPSHOT);
  const presP = once(phone, EV.PRESENCE);
  const snap = await snapP;
  assert.strictEqual(snap.bots.length, 1); assert.strictEqual(snap.maxActive, 5);
  assert.strictEqual((await presP).desktopOnline, true);
  await new Promise((r) => setTimeout(r, 100));
  console.log('ok  phone connected, got presence + sanitized cached snapshot');

  // commands: validated, relayed, acknowledged
  const seen = [];
  desk.on(EV.COMMAND, (c, ack) => { seen.push(c); ack({ ok: true, data: { echoed: c.action } }); });
  const r1 = await emitAck(phone, EV.COMMAND, { action: 'bot.start', botId: 'b1', evil: 'x' });
  assert.deepStrictEqual(r1, { ok: true, data: { echoed: 'bot.start' } });
  assert.deepStrictEqual(seen[0], { action: 'bot.start', botId: 'b1' });
  const r2 = await emitAck(phone, EV.COMMAND, { action: 'shell.exec', cmd: 'calc.exe' });
  assert.strictEqual(r2.error.code, 'UNSUPPORTED_ACTION');
  const r3 = await emitAck(phone, EV.COMMAND, { action: 'bot.chat', botId: 'b1', message: 'x'.repeat(300) });
  assert.strictEqual(r3.error.code, 'BAD_REQUEST');
  const r4 = await emitAck(phone, EV.COMMAND, { action: 'bot.chat', botId: '../etc', message: 'hi' });
  assert.strictEqual(r4.error.code, 'BAD_REQUEST');
  assert.strictEqual(seen.length, 1);
  console.log('ok  commands validated + relayed + acknowledged; shell/invalid rejected before reaching desktop');

  // streams desktop -> phone
  const stP = once(phone, EV.BOT_STATUS); const lgP = once(phone, EV.BOT_LOG); const chP = once(phone, EV.BOT_CHAT);
  desk.emit(EV.BOT_STATUS, { bot: { ...bot, status: 'online', connectedAt: Date.now() } });
  desk.emit(EV.BOT_LOG, { botId: 'b1', entry: { t: Date.now(), k: 'info', m: 'hello' } });
  desk.emit(EV.BOT_CHAT, { botId: 'b1', entry: { t: Date.now(), k: 'chat', m: '<Steve> hi' } });
  const st = await stP;
  assert.strictEqual(st.bot.status, 'online'); assert.strictEqual(st.activeCount, 1);
  assert.strictEqual((await lgP).entry.m, 'hello'); assert.strictEqual((await chP).entry.k, 'chat');
  console.log('ok  status/log/chat streamed to phone');

  // desktop sees phone presence
  const pres = await emitAck(desk, EV.D_PHONES_LIST, {});
  assert.strictEqual(pres.data.phones.length, 1); assert.strictEqual(pres.data.phones[0].online, true);

  // desktop offline -> phone told, commands fail meaningfully
  desk.close();
  assert.strictEqual((await once(phone, EV.PRESENCE)).desktopOnline, false);
  assert.strictEqual((await emitAck(phone, EV.COMMAND, { action: 'bots.stopAll' })).error.code, 'DESKTOP_OFFLINE');
  const desk2 = connect(base, { auth: { role: 'desktop', deviceId, token }, transports: ['websocket'], reconnection: false });
  cleanup.push(desk2);
  await once(desk2, EV.PRESENCE);
  console.log('ok  desktop offline/online presence + DESKTOP_OFFLINE error');

  // revoke from desktop
  const revoked = once(phone, EV.REVOKED);
  const rv = await emitAck(desk2, EV.D_PHONES_REVOKE, { phoneId: done.body.phoneId });
  assert.ok(rv.ok); await revoked;
  assert.strictEqual(await expectConnectError(base, { role: 'phone', token: done.body.token }), 'unauthorized');
  assert.strictEqual((await emitAck(desk2, EV.D_PHONES_REVOKE, { phoneId: done.body.phoneId })).error.code, 'NOT_FOUND');
  console.log('ok  revoke disconnects phone and invalidates token');

  // phone self-unpair
  const pc3 = await emitAck(desk2, EV.D_PAIRING_CREATE, {});
  const d2 = await post(base, '/api/pair/complete', { code: pc3.data.code, deviceName: 'Second' });
  assert.strictEqual((await post(base, '/api/phone/unpair', {}, { authorization: 'Bearer ' + d2.body.token })).status, 200);
  assert.strictEqual((await post(base, '/api/phone/unpair', {}, { authorization: 'Bearer ' + d2.body.token })).status, 401);
  console.log('ok  phone self-unpair');

  // phone limit
  for (let i = 0; i < 5; i++) {
    const c = await emitAck(desk2, EV.D_PAIRING_CREATE, {});
    const r = await post(base, '/api/pair/complete', { code: c.data.code, deviceName: 'P' + i });
    assert.strictEqual(r.status, 201);
  }
  const c6 = await emitAck(desk2, EV.D_PAIRING_CREATE, {});
  assert.strictEqual((await post(base, '/api/pair/complete', { code: c6.data.code, deviceName: 'P6' })).status, 409);
  console.log('ok  paired phone limit');

  cleanup.forEach((s) => s.close());
  io.close(); server.close();
  console.log('\nALL CLOUD E2E TESTS PASSED');
  process.exit(0);
})().catch((e) => { console.error('TEST FAILED:', e); process.exit(1); });
