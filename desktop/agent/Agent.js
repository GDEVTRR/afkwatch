'use strict';
const os = require('os');
const { EventEmitter } = require('events');
const { io } = require('socket.io-client');
const { EV, fail } = require('./protocol');
const { createCommandHandler } = require('./commands');
const { normalizeCloudUrl } = require('../services/validation');

/** Simple token bucket so a chat flood cannot saturate the uplink. */
function bucket(rate, burst) {
  let t = burst; let last = Date.now();
  return () => { const n = Date.now(); t = Math.min(burst, t + ((n - last) / 1000) * rate); last = n; if (t >= 1) { t -= 1; return true; } return false; };
}

/**
 * Cloud agent: owns the single Socket.IO connection, forwards bot events (only while a phone is online),
 * and executes validated commands. Events: 'state' ({state, error, phonesOnline, registered}), 'phones-changed', 'paired'.
 */
class Agent extends EventEmitter {
  constructor({ store, manager, deviceName }) {
    super();
    this.store = store; this.manager = manager;
    this.deviceName = deviceName || os.hostname();
    this.socket = null; this._retry = null;
    this.state = 'disconnected'; this.error = ''; this.phonesOnline = 0;
    this._handle = createCommandHandler(manager);
    this._allow = bucket(60, 200);
    this._attachManager();
  }

  _attachManager() {
    const ready = () => this.socket && this.socket.connected;
    this.manager.on('snapshot', (snap) => { if (ready()) this.socket.emit(EV.BOTS_SNAPSHOT, snap); });
    this.manager.on('status', (bot) => { if (ready()) this.socket.emit(EV.BOT_STATUS, { bot }); });
    // Logs/chat are only sent while at least one phone is watching: zero uplink traffic otherwise.
    this.manager.on('log', (botId, entry) => { if (ready() && this.phonesOnline > 0 && this._allow()) this.socket.emit(EV.BOT_LOG, { botId, entry }); });
    this.manager.on('chat', (botId, entry) => { if (ready() && this.phonesOnline > 0 && this._allow()) this.socket.emit(EV.BOT_CHAT, { botId, entry }); });
  }

  _set(state, error = '') {
    this.state = state; this.error = error;
    this.emit('state', this.status());
  }

  status() {
    const reg = this.store.getCloud();
    return { state: this.state, error: this.error, phonesOnline: this.phonesOnline, registered: Boolean(reg), origin: reg ? reg.origin : this.store.settings.cloudUrl };
  }

  async _register(origin, registrationKey) {
    const res = await fetch(origin + '/api/desktop/register', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ name: this.deviceName, registrationKey: registrationKey || undefined }),
      signal: AbortSignal.timeout(20000),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error((body.error && body.error.message) || `Registration failed (${res.status})`);
    if (!body.deviceId || !body.token) throw new Error('Unexpected registration response');
    this.store.setCloud({ origin, deviceId: body.deviceId, token: body.token });
  }

  /** Connect (registering this desktop on first use). Safe to call repeatedly: never creates a second socket. */
  async connect({ registrationKey } = {}) {
    this.disconnect(false);
    let origin;
    try { origin = normalizeCloudUrl(this.store.settings.cloudUrl); } catch (e) { this._set('error', e.message); throw e; }
    this._set('connecting');
    try {
      let reg = this.store.getCloud();
      if (!reg || reg.origin !== origin) { await this._register(origin, registrationKey); reg = this.store.getCloud(); }
      this._open(origin, reg);
    } catch (e) { this._set('error', e.message); throw e; }
  }

  _open(origin, reg) {
    const s = io(origin, {
      auth: { role: 'desktop', deviceId: reg.deviceId, token: reg.token },
      transports: ['websocket'],               // skip long-polling: one persistent connection
      reconnection: true, reconnectionDelay: 2000, reconnectionDelayMax: 60000, randomizationFactor: 0.5,
      timeout: 20000,
    });
    this.socket = s;
    s.on('connect', () => { this._set('connected'); s.emit(EV.BOTS_SNAPSHOT, this.manager.snapshot()); });
    s.on('disconnect', (why) => {
      this.phonesOnline = 0;
      if (this.socket !== s) return;
      if (why === 'io client disconnect') { this._set('disconnected'); return; }
      this._set('connecting', 'Connection lost, retrying');
      // socket.io only auto-reconnects on transport errors; after a server-side disconnect (e.g. a cloud
      // redeploy calling io.close()) we must reconnect ourselves. One timer at most.
      if (why === 'io server disconnect' && !this._retry) {
        this._retry = setTimeout(() => { this._retry = null; if (this.socket === s && !s.connected) s.connect(); }, 3000);
      }
    });
    s.on('connect_error', (e) => {
      if (e && e.message === 'unauthorized') {
        s.disconnect(); this._set('error', 'This PC is no longer registered on the server. Use "Reset registration" and connect again.');
      } else this._set('connecting', 'Cannot reach server: ' + (e && e.message));
    });
    s.on(EV.REPLACED, () => { s.disconnect(); this._set('error', 'Another instance of Bot Remote connected with the same registration.'); });
    s.on(EV.PRESENCE, (p) => { if (p && Number.isInteger(p.phonesOnline)) { this.phonesOnline = p.phonesOnline; this.emit('state', this.status()); } });
    s.on(EV.PHONES_CHANGED, () => this.emit('phones-changed'));
    s.on(EV.PAIRING_COMPLETED, (p) => this.emit('paired', p));
    s.on(EV.COMMAND, async (cmd, ack) => {
      const reply = typeof ack === 'function' ? ack : () => {};
      try { reply(await this._handle(cmd)); } catch (e) { reply(fail('ERROR', 'Command failed')); }
    });
  }

  disconnect(emit = true) {
    if (this._retry) { clearTimeout(this._retry); this._retry = null; }
    if (this.socket) { const s = this.socket; this.socket = null; s.removeAllListeners(); s.disconnect(); }
    this.phonesOnline = 0;
    if (emit) this._set('disconnected');
  }

  resetRegistration() { this.disconnect(); this.store.setCloud(null); this._set('disconnected'); }

  _call(event, payload) {
    return new Promise((resolve, reject) => {
      if (!this.socket || !this.socket.connected) return reject(new Error('Not connected to the cloud'));
      return this.socket.timeout(15000).emit(event, payload, (err, res) => {
        if (err) return reject(new Error('Cloud did not answer in time'));
        if (!res || !res.ok) return reject(new Error((res && res.error && res.error.message) || 'Request failed'));
        return resolve(res.data);
      });
    });
  }

  /** Returns the payload to render as a QR code: {v, u, c} + expiry. */
  async createPairing() {
    const d = await this._call(EV.D_PAIRING_CREATE, {});
    const reg = this.store.getCloud();
    return { payload: { v: 1, u: reg.origin, c: d.code }, expiresAt: d.expiresAt };
  }
  async listPhones() { return (await this._call(EV.D_PHONES_LIST, {})).phones; }
  async revokePhone(phoneId) { await this._call(EV.D_PHONES_REVOKE, { phoneId }); }
}

module.exports = { Agent };
