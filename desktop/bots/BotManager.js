'use strict';
const { EventEmitter } = require('events');
const crypto = require('crypto');
const { BotInstance } = require('./BotInstance');
const { LIMITS } = require('../agent/protocol');
const { validateBotConfig } = require('../services/validation');

class ManagerError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

/** Owns every BotInstance; enforces the 5-active-bot limit and the one-copy-per-bot rule. */
class BotManager extends EventEmitter {
  constructor({ store, profilesDir, mineflayer }) {
    super();
    this.store = store; this.profilesDir = profilesDir;
    this._mineflayer = mineflayer || require('mineflayer');
    this.instances = new Map();
    for (const cfg of store.bots) this._add(cfg);
  }

  _add(cfg) {
    const inst = new BotInstance(cfg, { profilesDir: this.profilesDir, mineflayer: this._mineflayer });
    inst.on('status', (view) => this.emit('status', view));
    inst.on('log', (e) => this.emit('log', inst.config.id, e));
    inst.on('chat', (e) => this.emit('chat', inst.config.id, e));
    this.instances.set(cfg.id, inst);
    return inst;
  }

  _get(id) {
    const i = this.instances.get(id);
    if (!i) throw new ManagerError('NOT_FOUND', 'Bot not found');
    return i;
  }

  list() { return [...this.instances.values()].map((i) => i.view()); }
  snapshot() {
    const bots = this.list();
    return { bots, activeCount: this.activeCount(), maxActive: LIMITS.MAX_ACTIVE_BOTS };
  }
  activeCount() { let n = 0; for (const i of this.instances.values()) if (i.active) n++; return n; }
  _persist() { this.store.setBots([...this.instances.values()].map((i) => i.config)); }
  _emitSnapshot() { this.emit('snapshot', this.snapshot()); }

  save(input) {
    const existing = input && input.id ? this.instances.get(input.id) : null;
    if (input && input.id && !existing) throw new ManagerError('NOT_FOUND', 'Bot not found');
    if (existing && existing.active) throw new ManagerError('BOT_RUNNING', 'Stop the bot before editing it');
    if (!existing && this.instances.size >= LIMITS.MAX_CONFIGURED_BOTS) {
      throw new ManagerError('LIMIT_REACHED', `At most ${LIMITS.MAX_CONFIGURED_BOTS} bots can be configured`);
    }
    const cfg = validateBotConfig(input, existing ? existing.config.id : undefined);
    if (existing) { existing.config = cfg; } else { this._add(cfg); }
    this._persist(); this._emitSnapshot();
    return this._get(cfg.id).view();
  }

  remove(id) {
    const inst = this._get(id);
    inst.dispose(); this.instances.delete(id);
    this._persist(); this._emitSnapshot();
  }

  start(id) {
    const inst = this._get(id);
    if (inst.active) return { alreadyRunning: true };
    if (this.activeCount() >= LIMITS.MAX_ACTIVE_BOTS) {
      throw new ManagerError('LIMIT_REACHED', `Maximum of ${LIMITS.MAX_ACTIVE_BOTS} active bots reached`);
    }
    const key = (c) => `${c.host.toLowerCase()}:${c.port}:${c.username.toLowerCase()}`;
    for (const other of this.instances.values()) {
      if (other !== inst && other.active && key(other.config) === key(inst.config)) {
        throw new ManagerError('DUPLICATE_ACCOUNT', `"${other.config.name}" already uses this account on this server`);
      }
    }
    inst.start();
    return { started: true };
  }

  stop(id) { this._get(id).stop(); return { stopped: true }; }

  startAll() {
    const started = []; const skipped = [];
    for (const [id, inst] of this.instances) {
      if (inst.active) continue;
      try { this.start(id); started.push(id); } catch (e) { skipped.push({ id, reason: e.code || 'ERROR' }); }
    }
    return { started, skipped };
  }

  stopAll() {
    const stopped = [];
    for (const [id, inst] of this.instances) if (inst.active) { inst.stop(); stopped.push(id); }
    return { stopped };
  }

  chat(id, message) { this._get(id).sendChat(message); return { sent: true }; }
  logs(id, limit = 100) { return this._get(id).logs.last(limit); }
  clearLogs(id) { this._get(id).logs.clear(); }
  newId() { return crypto.randomUUID(); }

  /** Stop everything and release all resources (app quit). */
  dispose() { for (const i of this.instances.values()) i.dispose(); this.instances.clear(); this.removeAllListeners(); }
}

module.exports = { BotManager, ManagerError };
