'use strict';
const express = require('express');
const { limiter } = require('../middleware/security');
const { PairingError } = require('../services/pairing');

const CODE_RE = /^[A-Za-z0-9_-]{16,128}$/;
const clean = (s, max) => String(s).replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, max);
const err = (res, status, code, message) => res.status(status).json({ error: { code, message } });

function createApiRouter({ cfg, store, security, pairing, gateway }) {
  const r = express.Router();
  r.use(express.json({ limit: '4kb' }));

  // Desktop registration: returns the desktop's long-lived secret ONCE. Only its hash is stored.
  r.post('/desktop/register', limiter(60 * 60 * 1000, 20), async (req, res, next) => {
    try {
      const b = req.body || {};
      if (cfg.registrationKey && !(typeof b.registrationKey === 'string' && security.safeEqual(b.registrationKey, cfg.registrationKey))) {
        return err(res, 403, 'FORBIDDEN', 'Invalid registration key');
      }
      const name = clean(b.name || 'Desktop', 40) || 'Desktop';
      const id = 'dsk_' + security.randomToken(12);
      const token = security.randomToken(32);
      await store.createDesktop({ id, name, tokenHash: security.hash(token) });
      return res.status(201).json({ deviceId: id, token });
    } catch (e) { return next(e); }
  });

  // Phone completes pairing with the QR code. Never returns any desktop credential.
  r.post('/pair/complete', limiter(60 * 1000, 15), async (req, res, next) => {
    try {
      const b = req.body || {};
      if (typeof b.code !== 'string' || !CODE_RE.test(b.code)) return err(res, 400, 'INVALID_OR_EXPIRED_CODE', 'Pairing code is invalid or expired');
      const name = clean(typeof b.deviceName === 'string' ? b.deviceName : 'iPhone', 40) || 'iPhone';
      const { phone, token } = await pairing.complete(b.code, name);
      gateway.notifyPaired(phone.desktopId, phone);
      return res.status(201).json({ phoneId: phone.id, token });
    } catch (e) {
      if (e instanceof PairingError) return err(res, e.code === 'PHONE_LIMIT' ? 409 : 400, e.code, e.message);
      return next(e);
    }
  });

  // Phone disconnects itself (revokes its own credential).
  r.post('/phone/unpair', limiter(60 * 1000, 15), async (req, res, next) => {
    try {
      const m = /^Bearer ([A-Za-z0-9_-]{20,128})$/.exec(req.get('authorization') || '');
      if (!m) return err(res, 401, 'UNAUTHORIZED', 'Missing token');
      const phone = await store.getPhoneByTokenHash(security.hash(m[1]));
      if (!phone) return err(res, 401, 'UNAUTHORIZED', 'Unknown token');
      await store.deletePhone(phone.desktopId, phone.id);
      gateway.revokePhone(phone.desktopId, phone.id);
      return res.json({ ok: true });
    } catch (e) { return next(e); }
  });

  return r;
}
module.exports = { createApiRouter };
