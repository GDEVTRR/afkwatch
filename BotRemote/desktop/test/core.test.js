'use strict';
/* Unit tests for the desktop core using a fake mineflayer (no Minecraft server needed). */
const assert = require('assert');
const os = require('os');
const path = require('path');
const fs = require('fs');
const { EventEmitter } = require('events');
const { ConfigStore } = require('../services/ConfigStore');
const { BotManager } = require('../bots/BotManager');
const { LogBuffer } = require('../services/LogBuffer');
const { createCommandHandler } = require('../agent/commands');
const { validateBotConfig, normalizeCloudUrl } = require('../services/validation');

class FakeBot extends EventEmitter {
  constructor(o) { super(); this.opts = o; this.version = '1.20.4'; this.ended = false; this.chats = []; }
  chat(m) { this.chats.push(m); }
  end() { this.ended = true; setImmediate(() => this.emit('end', 'fake')); }
}
const created = [];
const fakeMf = { createBot: (o) => { const b = new FakeBot(o); created.push(b); return b; } };
const tick = (ms = 20) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'br-'));
  const store = new ConfigStore(dir);
  const mgr = new BotManager({ store, profilesDir: dir, mineflayer: fakeMf });

  // validation
  assert.throws(() => validateBotConfig({ name: 'x', host: 'bad host', port: 25565, username: 'abc', auth: 'offline' }), /address/);
  assert.throws(() => validateBotConfig({ name: 'x', host: 'a.com', port: 70000, username: 'abc', auth: 'offline' }), /Port/);
  assert.throws(() => validateBotConfig({ name: 'x', host: 'a.com', port: 1, username: 'a b', auth: 'offline' }), /Username/);
  assert.throws(() => validateBotConfig({ name: 'x', host: 'a.com', port: 1, username: 'abc', auth: 'offline', version: 'abc' }), /Version/);
  assert.strictEqual(normalizeCloudUrl('https://x.onrender.com/path'), 'https://x.onrender.com');
  assert.throws(() => normalizeCloudUrl('http://example.com'), /https/);
  assert.strictEqual(normalizeCloudUrl('http://localhost:3000'), 'http://localhost:3000');
  console.log('ok  validation');

  // ring buffer bound
  const lb = new LogBuffer(3); for (let i = 0; i < 10; i++) lb.push(i);
  assert.deepStrictEqual(lb.last(), [7, 8, 9]); assert.deepStrictEqual(lb.last(2), [8, 9]);
  console.log('ok  log buffer bounded');

  // create 7 bots; only 5 can be active
  const ids = [];
  for (let i = 0; i < 7; i++) ids.push(mgr.save({ name: 'B' + i, host: 'mc.example.com', port: 25565, username: 'Bot_' + i, auth: 'offline', autoReconnect: true, reconnectDelaySec: 1 }).id);
  assert.strictEqual(fs.existsSync(path.join(dir, 'config.json')), true);
  const res = mgr.startAll();
  assert.strictEqual(res.started.length, 5); assert.strictEqual(res.skipped.length, 2);
  assert.strictEqual(res.skipped[0].reason, 'LIMIT_REACHED');
  assert.strictEqual(created.length, 5);
  assert.throws(() => mgr.start(ids[6]), /Maximum/);
  assert.deepStrictEqual(mgr.start(ids[0]), { alreadyRunning: true });  // no duplicate copy
  assert.strictEqual(created.length, 5);
  console.log('ok  five-bot limit, no duplicate instances');

  // duplicate account protection
  mgr.stop(ids[4]);
  const dup = mgr.save({ name: 'dup', host: 'MC.example.com', port: 25565, username: 'bot_0', auth: 'offline' }).id;
  assert.throws(() => mgr.start(dup), /already uses/);
  mgr.remove(dup);

  // spawn -> online, chat, logs
  const events = [];
  mgr.on('status', (v) => events.push(v.status));
  created[0].emit('spawn'); await tick();
  assert.strictEqual(mgr.list().find((b) => b.id === ids[0]).status, 'online');
  created[0].emit('messagestr', '<Steve> hello', 'chat'); created[0].emit('messagestr', 'actionbar', 'game_info');
  assert.deepStrictEqual(mgr.logs(ids[0]).filter((l) => l.k === 'chat').map((l) => l.m), ['<Steve> hello']);
  mgr.chat(ids[0], 'hi there'); assert.deepStrictEqual(created[0].chats, ['hi there']);
  assert.throws(() => mgr.chat(ids[1], 'x'), /not online/);
  console.log('ok  spawn/online, chat in/out');

  // edit while running is rejected
  assert.throws(() => mgr.save({ id: ids[0], name: 'n', host: 'a.com', port: 1, username: 'abc', auth: 'offline' }), /Stop the bot/);

  // reconnect after end, then stop cancels reconnect + disposes
  created[0].emit('end', 'server closed'); await tick(5);
  assert.strictEqual(mgr.list().find((b) => b.id === ids[0]).status, 'reconnecting');
  await tick(1100);
  assert.strictEqual(created.length, 6, 'reconnect created exactly one new connection');
  mgr.stop(ids[0]); await tick(1300);
  assert.strictEqual(created.length, 6, 'stop cancelled further reconnects');
  assert.strictEqual(created[5].ended, true);
  console.log('ok  reconnect (single timer), stop cancels + ends connection');

  // stale events from an old connection are ignored
  const before = mgr.list().find((b) => b.id === ids[0]).status;
  created[0].emit('spawn'); await tick();
  assert.strictEqual(mgr.list().find((b) => b.id === ids[0]).status, before);
  console.log('ok  stale connection events ignored');

  // autoReconnect disabled -> stays stopped
  mgr.stopAll();
  const noRc = mgr.save({ name: 'nr', host: 'a.com', port: 25565, username: 'NoRc', auth: 'offline', autoReconnect: false }).id;
  mgr.start(noRc); const nb = created[created.length - 1]; nb.emit('end', 'x'); await tick();
  assert.strictEqual(mgr.list().find((b) => b.id === noRc).status, 'stopped');
  console.log('ok  reconnect disabled respected');

  // command handler whitelist
  const h = createCommandHandler(mgr);
  assert.strictEqual((await h({ action: 'exec', cmd: 'dir' })).error.code, 'UNSUPPORTED_ACTION');
  assert.strictEqual((await h({ action: 'bot.start', botId: 'nope' })).error.code, 'NOT_FOUND');
  assert.ok((await h({ action: 'snapshot' })).data.maxActive === 5);
  assert.ok((await h({ action: 'bots.stopAll' })).ok);
  console.log('ok  command handler whitelist');

  // persistence
  const store2 = new ConfigStore(dir);
  assert.strictEqual(store2.bots.length, 8);
  store2.setCloud({ origin: 'https://x', deviceId: 'dsk_12345678', token: 'tok' });
  assert.ok(!fs.readFileSync(path.join(dir, 'config.json'), 'utf8').includes('"tok"'));
  assert.strictEqual(new ConfigStore(dir).getCloud().token, 'tok');
  console.log('ok  persistence (token not stored in cleartext)');

  mgr.dispose();
  fs.rmSync(dir, { recursive: true, force: true });
  console.log('\nDESKTOP CORE TESTS PASSED');
  process.exit(0);
})().catch((e) => { console.error('TEST FAILED', e); process.exit(1); });
