'use strict';
const crypto = require('crypto');

function createSecurity(pepper) {
  return {
    /** 256-bit URL-safe random token. */
    randomToken(bytes = 32) { return crypto.randomBytes(bytes).toString('base64url'); },
    /** HMAC-SHA256 of a (high entropy) token; only this hash is ever stored. */
    hash(token) { return crypto.createHmac('sha256', pepper).update(String(token)).digest('hex'); },
    safeEqual(a, b) {
      const x = Buffer.from(String(a)); const y = Buffer.from(String(b));
      return x.length === y.length && crypto.timingSafeEqual(x, y);
    },
  };
}

/** Tiny token bucket used for per-socket flood protection (no timers). */
function createBucket(ratePerSec, burst) {
  let tokens = burst; let last = Date.now();
  return {
    take() {
      const now = Date.now();
      tokens = Math.min(burst, tokens + ((now - last) / 1000) * ratePerSec);
      last = now;
      if (tokens >= 1) { tokens -= 1; return true; }
      return false;
    },
  };
}

module.exports = { createSecurity, createBucket };
