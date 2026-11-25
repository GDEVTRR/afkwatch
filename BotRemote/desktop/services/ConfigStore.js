'use strict';
const fs = require('fs');
const path = require('path');

const DEFAULTS = () => ({
  version: 1,
  settings: { cloudUrl: '', autoConnect: true, launchAtLogin: false },
  bots: [],
  cloud: null, // { origin, deviceId, tokenEnc }
});

/**
 * Persistent JSON config in the user-data directory. Writes are synchronous + atomic (tmp file + rename)
 * and happen only when something changes, so there are no timers or background I/O.
 * `codec` encrypts the cloud token (Electron safeStorage / Windows DPAPI in the app).
 */
class ConfigStore {
  constructor(dir, codec) {
    this.dir = dir; this.file = path.join(dir, 'config.json');
    this.codec = codec || { encrypt: (s) => 'plain:' + Buffer.from(s).toString('base64'), decrypt: (s) => Buffer.from(s.replace(/^plain:/, ''), 'base64').toString() };
    fs.mkdirSync(dir, { recursive: true });
    this.data = this._load();
  }
  _load() {
    try {
      const raw = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      const d = DEFAULTS();
      return { ...d, ...raw, settings: { ...d.settings, ...(raw.settings || {}) }, bots: Array.isArray(raw.bots) ? raw.bots : [] };
    } catch (e) {
      if (e.code !== 'ENOENT') {
        try { fs.renameSync(this.file, this.file + '.corrupt-' + Date.now()); } catch { /* ignore */ }
      }
      return DEFAULTS();
    }
  }
  save() {
    const tmp = this.file + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(this.data, null, 2), { mode: 0o600 });
    fs.renameSync(tmp, this.file);
  }
  get settings() { return this.data.settings; }
  setSettings(patch) { Object.assign(this.data.settings, patch); this.save(); }
  get bots() { return this.data.bots; }
  setBots(bots) { this.data.bots = bots; this.save(); }
  getCloud() {
    const c = this.data.cloud;
    if (!c || !c.tokenEnc) return null;
    try { return { origin: c.origin, deviceId: c.deviceId, token: this.codec.decrypt(c.tokenEnc) }; } catch { return null; }
  }
  setCloud(c) {
    this.data.cloud = c ? { origin: c.origin, deviceId: c.deviceId, tokenEnc: this.codec.encrypt(c.token) } : null;
    this.save();
  }
}
module.exports = { ConfigStore };
