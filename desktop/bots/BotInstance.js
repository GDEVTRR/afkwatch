'use strict';
const { EventEmitter } = require('events');
const path = require('path');
const { LogBuffer } = require('../services/LogBuffer');
const { LIMITS } = require('../agent/protocol');

const CTRL = /[\u0000-\u0009\u000b-\u001f\u007f]/g;
const clip = (s) => String(s).replace(CTRL, '').slice(0, LIMITS.MAX_LOG_LENGTH);

/** Flatten a Minecraft JSON chat component (kick reasons etc.) to plain text. */
function flattenChat(v) {
  if (v == null) return '';
  if (typeof v === 'string') {
    try { const j = JSON.parse(v); return typeof j === 'string' ? j : flattenChat(j); } catch { return v; }
  }
  if (Array.isArray(v)) return v.map(flattenChat).join('');
  if (typeof v === 'object') {
    if (v.value !== undefined && v.type !== undefined) return flattenChat(v.value); // NBT-ish
    let s = typeof v.text === 'string' ? v.text : (typeof v.translate === 'string' ? v.translate : '');
    if (v.extra) s += flattenChat(v.extra);
    return s;
  }
  return String(v);
}

/**
 * One Mineflayer bot with its own lifecycle. Guarantees:
 *  - at most one live connection and one reconnect timer per instance
 *  - every callback from an old connection is ignored (generation counter)
 *  - stop()/dispose() always end the connection and clear timers
 */
class BotInstance extends EventEmitter {
  constructor(config, { profilesDir, mineflayer }) {
    super();
    this.config = config;
    this.profilesDir = profilesDir;
    this._mineflayer = mineflayer; // injectable for tests
    this.logs = new LogBuffer(500);
    this.status = 'stopped';
    this.connectedAt = null;
    this.serverVersion = '';
    this.lastError = '';
    this._bot = null;
    this._timer = null;
    this._gen = 0;
    this._wantRun = false;
  }

  get active() { return this.status !== 'stopped'; }

  view() {
    const c = this.config;
    return {
      id: c.id, name: c.name, host: c.host, port: c.port, username: c.username, auth: c.auth, version: c.version,
      autoReconnect: c.autoReconnect, reconnectDelaySec: c.reconnectDelaySec,
      status: this.status, connectedAt: this.connectedAt, serverVersion: this.serverVersion, lastError: this.lastError,
    };
  }

  log(kind, message) {
    const entry = { t: Date.now(), k: kind, m: clip(message) };
    if (!entry.m) return;
    this.logs.push(entry);
    this.emit(kind === 'chat' ? 'chat' : 'log', entry);
  }

  _setStatus(status) {
    if (this.status === status) return;
    this.status = status;
    if (status !== 'online') this.connectedAt = null;
    this.emit('status', this.view());
  }

  start() {
    if (this.active) return false;          // never run two copies of the same bot
    this._wantRun = true;
    this.lastError = '';
    this._connect();
    return true;
  }

  stop() {
    this._wantRun = false;
    this._clearTimer();
    this._teardown('Stopped by user');
    if (this.status !== 'stopped') { this.log('system', 'Bot stopped'); }
    this.serverVersion = '';
    this._setStatus('stopped');
  }

  dispose() { this.stop(); this.removeAllListeners(); }

  sendChat(message) {
    if (!this._bot || this.status !== 'online') throw Object.assign(new Error('Bot is not online'), { code: 'NOT_ONLINE' });
    this._bot.chat(message);
    this.log('out', '> ' + message);
  }

  _clearTimer() { if (this._timer) { clearTimeout(this._timer); this._timer = null; } }

  _teardown(reason) {
    this._gen++; // invalidate all callbacks of the old connection
    const b = this._bot; this._bot = null;
    if (!b) return;
    try { b.on('error', () => {}); } catch { /* ignore */ }
    try { b.end(reason); } catch { /* ignore */ }
  }

  _connect() {
    this._clearTimer();
    this._teardown('Reconnecting');
    const gen = this._gen;
    const c = this.config;
    this._setStatus('connecting');
    this.log('system', `Connecting to ${c.host}:${c.port} as ${c.username} (${c.auth}${c.version ? ', ' + c.version : ', auto version'})`);

    let bot;
    try {
      const opts = {
        host: c.host, port: c.port, username: c.username, auth: c.auth,
        hideErrors: true, checkTimeoutInterval: 30000, connectTimeout: 30000,
      };
      if (c.version) opts.version = c.version;
      if (c.auth === 'microsoft') {
        opts.profilesFolder = path.join(this.profilesDir, c.id);
        opts.onMsaCode = (data) => {
          if (gen !== this._gen) return;
          this.log('system', `Microsoft sign-in required: open ${data.verification_uri} and enter code ${data.user_code}`);
        };
      }
      bot = this._mineflayer.createBot(opts);
    } catch (e) {
      this.lastError = clip(e.message || e);
      this.log('error', 'Failed to start: ' + this.lastError);
      this._onEnded(gen);
      return;
    }
    this._bot = bot;
    const live = (fn) => (...a) => { if (gen === this._gen) fn(...a); };

    bot.once('login', live(() => this.log('info', 'Logged in, waiting for spawn')));
    bot.once('spawn', live(() => {
      this.connectedAt = Date.now();
      this.serverVersion = String(bot.version || '');
      this._setStatus('online');
      this.log('info', `Spawned (server version ${this.serverVersion || 'unknown'})`);
    }));
    bot.on('messagestr', live((msg, position) => { if (position !== 'game_info' && msg) this.log('chat', msg); }));
    bot.on('kicked', live((reason) => {
      this.lastError = clip('Kicked: ' + flattenChat(reason));
      this.log('error', this.lastError);
    }));
    bot.on('error', live((err) => {
      this.lastError = clip(err && (err.code ? `${err.code}: ${err.message}` : err.message) || 'Unknown error');
      this.log('error', this.lastError);
    }));
    bot.on('end', live((reason) => {
      this.log('info', 'Disconnected' + (reason ? ` (${clip(flattenChat(reason))})` : ''));
      this._bot = null;
      this._onEnded(gen);
    }));
  }

  _onEnded() {
    this._teardown('ended');
    this.connectedAt = null;
    if (!this._wantRun) { this._setStatus('stopped'); return; }
    if (!this.config.autoReconnect) {
      this._wantRun = false;
      this._setStatus('stopped');
      return;
    }
    this._setStatus('reconnecting');
    const delay = this.config.reconnectDelaySec * 1000;
    this.log('system', `Reconnecting in ${this.config.reconnectDelaySec}s`);
    this._clearTimer();
    this._timer = setTimeout(() => { this._timer = null; if (this._wantRun) this._connect(); }, delay);
  }
}

module.exports = { BotInstance, flattenChat };
