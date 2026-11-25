'use strict';
const crypto = require('crypto');

function loadConfig(env = process.env) {
  const isProd = env.NODE_ENV === 'production';
  const cfg = {
    isProd,
    port: Number(env.PORT) || 3000,
    databaseUrl: env.DATABASE_URL || '',
    databaseSsl: env.DATABASE_SSL === 'true',
    registrationKey: env.REGISTRATION_KEY || '',
    allowMemoryStore: env.ALLOW_MEMORY_STORE === 'true',
    pepper: env.TOKEN_PEPPER || '',
    trustProxy: env.TRUST_PROXY === undefined ? (isProd ? 1 : false) : parseTrust(env.TRUST_PROXY),
  };
  if (isProd) {
    if (cfg.pepper.length < 32) throw new Error('TOKEN_PEPPER must be set to at least 32 characters in production');
    if (!cfg.databaseUrl && !cfg.allowMemoryStore) {
      throw new Error('DATABASE_URL is required in production (pairing data must be persistent)');
    }
  } else if (!cfg.pepper) {
    cfg.pepper = crypto.randomBytes(32).toString('hex'); // dev only: tokens do not survive restarts anyway
  }
  return cfg;
}

function parseTrust(v) {
  if (v === 'true') return true;
  if (v === 'false' || v === '0') return false;
  const n = Number(v);
  return Number.isInteger(n) ? n : v;
}

module.exports = { loadConfig };
