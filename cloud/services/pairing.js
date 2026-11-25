'use strict';
const { LIMITS } = require('./protocol');

class PairingError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

function createPairingService({ store, security }) {
  return {
    /** Create a fresh single-use code (replaces any previous code of this desktop). */
    async createCode(desktopId) {
      const code = security.randomToken(24);
      const expiresAt = Date.now() + LIMITS.PAIRING_TTL_MS;
      await store.replacePairing(desktopId, security.hash(code), expiresAt);
      return { code, expiresAt };
    },
    /** Consume a code and create a phone credential. The phone token is returned exactly once. */
    async complete(code, deviceName) {
      const rec = await store.consumePairing(security.hash(code));
      if (!rec || rec.expiresAt < Date.now()) throw new PairingError('INVALID_OR_EXPIRED_CODE', 'Pairing code is invalid or expired');
      if ((await store.countPhones(rec.desktopId)) >= LIMITS.MAX_PHONES_PER_DESKTOP) {
        throw new PairingError('PHONE_LIMIT', `A desktop can have at most ${LIMITS.MAX_PHONES_PER_DESKTOP} paired phones`);
      }
      const token = security.randomToken(32);
      const phone = { id: 'ph_' + security.randomToken(9), desktopId: rec.desktopId, name: deviceName, tokenHash: security.hash(token) };
      await store.createPhone(phone);
      return { phone, token };
    },
  };
}
module.exports = { createPairingService, PairingError };
