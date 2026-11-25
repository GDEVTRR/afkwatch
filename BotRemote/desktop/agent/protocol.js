'use strict';
/**
 * Bot Remote wire protocol (shared by cloud and desktop).
 * THIS FILE MUST BE BYTE-IDENTICAL IN cloud/services/ and desktop/agent/.
 * Run `node scripts/check-protocol.js` from the repo root to verify.
 */

const PROTOCOL_VERSION = 1;

const EV = Object.freeze({
  // desktop -> cloud (acknowledged)
  D_PAIRING_CREATE: 'desktop:pairing:create',
  D_PHONES_LIST: 'desktop:phones:list',
  D_PHONES_REVOKE: 'desktop:phones:revoke',
  // desktop -> cloud -> phones (streams, no ack)
  BOTS_SNAPSHOT: 'bots:snapshot',
  BOT_STATUS: 'bot:status',
  BOT_LOG: 'bot:log',
  BOT_CHAT: 'bot:chat',
  // phone -> cloud -> desktop (acknowledged)
  COMMAND: 'command',
  // cloud -> desktop / phone
  PRESENCE: 'presence',
  PAIRING_COMPLETED: 'pairing:completed',
  PHONES_CHANGED: 'phones:changed',
  REVOKED: 'revoked',
  REPLACED: 'replaced',
});

const ACTIONS = Object.freeze([
  'bot.start', 'bot.stop', 'bots.startAll', 'bots.stopAll', 'bot.chat', 'bot.logs', 'snapshot',
]);

const LIMITS = Object.freeze({
  MAX_ACTIVE_BOTS: 5,
  MAX_CONFIGURED_BOTS: 20,
  MAX_PHONES_PER_DESKTOP: 5,
  MAX_CHAT_LENGTH: 256,
  MAX_LOG_LENGTH: 400,
  MAX_LOGS_PER_REQUEST: 200,
  PAIRING_TTL_MS: 5 * 60 * 1000,
});

const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const CONTROL_RE = /[\u0000-\u001f\u007f]/;
const STATUSES = ['stopped', 'connecting', 'online', 'reconnecting'];
const LOG_KINDS = ['info', 'chat', 'error', 'system', 'out'];

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const str = (v, max) => (typeof v === 'string' ? v.slice(0, max) : '');
const num = (v, min, max, def) => (Number.isFinite(v) ? Math.min(max, Math.max(min, Math.trunc(v))) : def);

function fail(code, message) { return { ok: false, error: { code, message } }; }

/** Validate a remote command. Returns {ok:true,value} or {ok:false,error}. */
function validateCommand(p) {
  if (!isObj(p)) return fail('BAD_REQUEST', 'Command must be an object');
  if (typeof p.action !== 'string' || !ACTIONS.includes(p.action)) {
    return fail('UNSUPPORTED_ACTION', 'Unsupported action');
  }
  const v = { action: p.action };
  const needsBot = ['bot.start', 'bot.stop', 'bot.chat', 'bot.logs'].includes(p.action);
  if (needsBot) {
    if (typeof p.botId !== 'string' || !ID_RE.test(p.botId)) return fail('BAD_REQUEST', 'Invalid botId');
    v.botId = p.botId;
  }
  if (p.action === 'bot.chat') {
    if (typeof p.message !== 'string') return fail('BAD_REQUEST', 'message must be a string');
    const m = p.message.trim();
    if (m.length < 1 || m.length > LIMITS.MAX_CHAT_LENGTH) {
      return fail('BAD_REQUEST', `message must be 1-${LIMITS.MAX_CHAT_LENGTH} characters`);
    }
    if (CONTROL_RE.test(m)) return fail('BAD_REQUEST', 'message contains control characters');
    v.message = m;
  }
  if (p.action === 'bot.logs') v.limit = num(p.limit, 1, LIMITS.MAX_LOGS_PER_REQUEST, 100);
  return { ok: true, value: v };
}

function sanitizeBot(b) {
  if (!isObj(b) || typeof b.id !== 'string' || !ID_RE.test(b.id)) return null;
  return {
    id: b.id,
    name: str(b.name, 40),
    host: str(b.host, 253),
    port: num(b.port, 1, 65535, 25565),
    username: str(b.username, 100),
    auth: b.auth === 'microsoft' ? 'microsoft' : 'offline',
    version: str(b.version, 16),
    autoReconnect: b.autoReconnect === true,
    reconnectDelaySec: num(b.reconnectDelaySec, 1, 3600, 10),
    status: STATUSES.includes(b.status) ? b.status : 'stopped',
    connectedAt: Number.isFinite(b.connectedAt) ? b.connectedAt : null,
    serverVersion: str(b.serverVersion, 16),
    lastError: str(b.lastError, 200),
  };
}

function sanitizeSnapshot(s) {
  if (!isObj(s) || !Array.isArray(s.bots)) return null;
  const bots = s.bots.slice(0, LIMITS.MAX_CONFIGURED_BOTS).map(sanitizeBot).filter(Boolean);
  return {
    bots,
    activeCount: bots.filter((b) => b.status !== 'stopped').length,
    maxActive: LIMITS.MAX_ACTIVE_BOTS,
  };
}

function sanitizeLog(e) {
  if (!isObj(e)) return null;
  return {
    t: Number.isFinite(e.t) ? e.t : Date.now(),
    k: LOG_KINDS.includes(e.k) ? e.k : 'info',
    m: str(e.m, LIMITS.MAX_LOG_LENGTH),
  };
}

module.exports = {
  PROTOCOL_VERSION, EV, ACTIONS, LIMITS, ID_RE, STATUSES, LOG_KINDS,
  validateCommand, sanitizeBot, sanitizeSnapshot, sanitizeLog, fail,
};
