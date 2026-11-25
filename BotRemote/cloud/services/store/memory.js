'use strict';
/** Non-persistent store for local development and tests ONLY. */
function createMemoryStore() {
  const desktops = new Map(); const pairings = new Map(); const phones = new Map();
  return {
    kind: 'memory',
    async init() {},
    async close() {},
    async createDesktop(d) { desktops.set(d.id, { ...d, createdAt: Date.now() }); },
    async getDesktop(id) { return desktops.get(id) || null; },
    async replacePairing(desktopId, codeHash, expiresAt) {
      for (const [k, v] of pairings) if (v.desktopId === desktopId || v.expiresAt < Date.now()) pairings.delete(k);
      pairings.set(codeHash, { desktopId, expiresAt });
    },
    async consumePairing(codeHash) {
      const p = pairings.get(codeHash); pairings.delete(codeHash);
      return p || null; // caller checks expiry
    },
    async countPhones(desktopId) { return [...phones.values()].filter((p) => p.desktopId === desktopId).length; },
    async createPhone(p) { phones.set(p.id, { ...p, createdAt: Date.now(), lastSeenAt: null }); },
    async getPhoneByTokenHash(h) { return [...phones.values()].find((p) => p.tokenHash === h) || null; },
    async touchPhone(id) { const p = phones.get(id); if (p) p.lastSeenAt = Date.now(); },
    async listPhones(desktopId) { return [...phones.values()].filter((p) => p.desktopId === desktopId); },
    async deletePhone(desktopId, phoneId) {
      const p = phones.get(phoneId);
      if (!p || p.desktopId !== desktopId) return false;
      phones.delete(phoneId); return true;
    },
  };
}
module.exports = { createMemoryStore };
