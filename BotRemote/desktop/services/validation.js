'use strict';
const crypto = require('crypto');
const { LIMITS } = require('../agent/protocol');

class ValidationError extends Error {
  constructor(message) { super(message); this.code = 'VALIDATION'; }
}

const HOST_RE = /^(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$/;
const OFFLINE_USER_RE = /^[A-Za-z0-9_]{3,16}$/;
const VERSION_RE = /^\d{1,2}\.\d{1,2}(\.\d{1,2})?$/;

/** Validate + normalize a bot configuration coming from the UI. Throws ValidationError. */
function validateBotConfig(input, existingId) {
  if (!input || typeof input !== 'object') throw new ValidationError('Invalid bot configuration');
  const name = String(input.name ?? '').replace(/[\u0000-\u001f\u007f]/g, '').trim();
  const host = String(input.host ?? '').trim();
  const username = String(input.username ?? '').trim();
  const auth = input.auth === 'microsoft' ? 'microsoft' : input.auth === 'offline' ? 'offline' : null;
  const port = Number(input.port ?? 25565);
  const version = String(input.version ?? '').trim();
  const delay = Number(input.reconnectDelaySec ?? 10);

  if (name.length < 1 || name.length > 40) throw new ValidationError('Name must be 1-40 characters');
  if (!HOST_RE.test(host)) throw new ValidationError('Invalid server address');
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new ValidationError('Port must be 1-65535');
  if (!auth) throw new ValidationError('Authentication must be "offline" or "microsoft"');
  if (auth === 'offline' && !OFFLINE_USER_RE.test(username)) throw new ValidationError('Username must be 3-16 letters, digits or underscores');
  if (auth === 'microsoft' && (username.length < 3 || username.length > 100 || /[\u0000-\u001f\u007f\s]/.test(username))) {
    throw new ValidationError('Microsoft account label must be 3-100 characters (no spaces)');
  }
  if (version !== '' && !VERSION_RE.test(version)) throw new ValidationError('Version must look like 1.20.4 (or empty for auto-detect)');
  if (!Number.isInteger(delay) || delay < 1 || delay > 3600) throw new ValidationError('Reconnect delay must be 1-3600 seconds');

  return {
    id: existingId || crypto.randomUUID(),
    name, host, port, username, auth, version,
    autoReconnect: input.autoReconnect !== false,
    reconnectDelaySec: delay,
  };
}

/** Cloud URL: https only, except loopback for local development. Returns the normalized origin. */
function normalizeCloudUrl(url) {
  let u;
  try { u = new URL(String(url).trim()); } catch { throw new ValidationError('Invalid cloud URL'); }
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(u.hostname);
  if (u.protocol !== 'https:' && !(u.protocol === 'http:' && loopback)) {
    throw new ValidationError('Cloud URL must use https:// (http:// is only allowed for localhost)');
  }
  if (u.username || u.password) throw new ValidationError('Cloud URL must not contain credentials');
  return u.origin;
}

module.exports = { ValidationError, validateBotConfig, normalizeCloudUrl, LIMITS };
