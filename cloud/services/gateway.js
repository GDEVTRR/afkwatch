'use strict';
const { EV, ID_RE, LIMITS, validateCommand, sanitizeSnapshot, sanitizeBot, sanitizeLog, fail } = require('./protocol');
const { createBucket } = require('./security');

const COMMAND_TIMEOUT_MS = 15000;
const noop = () => {};
const ackOf = (cb) => (typeof cb === 'function' ? cb : noop);
const phonesRoom = (desktopId) => `phones:${desktopId}`;
const phoneRoom = (phoneId) => `phone:${phoneId}`;

/**
 * Socket.IO routing. Authentication happens in io.use() (handshake), every event payload is validated,
 * and phones can only ever reach the ONE desktop they were paired with.
 */
function attachGateway(io, { store, security, pairing }) {
  const desktops = new Map();   // desktopId -> socket (at most one live socket per desktop)
  const snapshots = new Map();  // desktopId -> last sanitized snapshot (tiny; lets phones render instantly)

  const phonesOnline = (id) => io.sockets.adapter.rooms.get(phonesRoom(id))?.size || 0;
  const pushPhonesOnline = (id) => desktops.get(id)?.emit(EV.PRESENCE, { phonesOnline: phonesOnline(id) });

  // ---- Handshake authentication ------------------------------------------------------------
  io.use(async (socket, next) => {
    try {
      const a = socket.handshake.auth || {};
      if (typeof a.token !== 'string' || a.token.length < 20 || a.token.length > 128) return next(new Error('unauthorized'));
      if (a.role === 'desktop') {
        if (typeof a.deviceId !== 'string' || !/^[A-Za-z0-9_-]{8,64}$/.test(a.deviceId)) return next(new Error('unauthorized'));
        const d = await store.getDesktop(a.deviceId);
        if (!d || !security.safeEqual(d.tokenHash, security.hash(a.token))) return next(new Error('unauthorized'));
        socket.data = { role: 'desktop', desktopId: d.id };
        return next();
      }
      if (a.role === 'phone') {
        const p = await store.getPhoneByTokenHash(security.hash(a.token));
        if (!p) return next(new Error('unauthorized'));
        socket.data = { role: 'phone', desktopId: p.desktopId, phoneId: p.id, phoneName: p.name };
        return next();
      }
      return next(new Error('unauthorized'));
    } catch (e) {
      console.error('[auth] error:', e.message);
      return next(new Error('server_error'));
    }
  });

  io.on('connection', (socket) => {
    const bucket = socket.data.role === 'desktop' ? createBucket(150, 400) : createBucket(10, 30);
    socket.use((packet, next) => {
      if (bucket.take()) return next();
      const cb = packet[packet.length - 1];
      if (typeof cb === 'function') cb(fail('RATE_LIMITED', 'Too many events'));
      return undefined; // drop packet
    });
    socket.on('error', (e) => console.warn('[socket] error:', e && e.message));
    if (socket.data.role === 'desktop') onDesktop(socket); else onPhone(socket);
  });

  // ---- Desktop -----------------------------------------------------------------------------
  function onDesktop(socket) {
    const { desktopId } = socket.data;
    const prev = desktops.get(desktopId);
    if (prev && prev.id !== socket.id) { prev.emit(EV.REPLACED); prev.disconnect(true); }
    desktops.set(desktopId, socket);
    socket.join(`desktop:${desktopId}`);
    io.to(phonesRoom(desktopId)).emit(EV.PRESENCE, { desktopOnline: true });
    socket.emit(EV.PRESENCE, { phonesOnline: phonesOnline(desktopId) });

    socket.on(EV.D_PAIRING_CREATE, async (_p, cb) => {
      try {
        return ackOf(cb)({ ok: true, data: await pairing.createCode(desktopId) });
      } catch (e) { console.error('[pairing]', e.message); return ackOf(cb)(fail('SERVER_ERROR', 'Could not create pairing code')); }
    });

    socket.on(EV.D_PHONES_LIST, async (_p, cb) => {
      try {
        const list = await store.listPhones(desktopId);
        return ackOf(cb)({ ok: true, data: { phones: list.map((p) => ({
          id: p.id, name: p.name, createdAt: p.createdAt, lastSeenAt: p.lastSeenAt,
          online: Boolean(io.sockets.adapter.rooms.get(phoneRoom(p.id))?.size),
        })) } });
      } catch (e) { return ackOf(cb)(fail('SERVER_ERROR', 'Could not list phones')); }
    });

    socket.on(EV.D_PHONES_REVOKE, async (p, cb) => {
      try {
        if (!p || typeof p.phoneId !== 'string' || !ID_RE.test(p.phoneId)) return ackOf(cb)(fail('BAD_REQUEST', 'Invalid phoneId'));
        const removed = await store.deletePhone(desktopId, p.phoneId);
        if (!removed) return ackOf(cb)(fail('NOT_FOUND', 'Phone not found'));
        gateway.revokePhone(desktopId, p.phoneId);
        return ackOf(cb)({ ok: true });
      } catch (e) { return ackOf(cb)(fail('SERVER_ERROR', 'Could not revoke phone')); }
    });

    socket.on(EV.BOTS_SNAPSHOT, (p) => {
      const s = sanitizeSnapshot(p);
      if (!s) return;
      snapshots.set(desktopId, s);
      io.to(phonesRoom(desktopId)).emit(EV.BOTS_SNAPSHOT, s);
    });

    socket.on(EV.BOT_STATUS, (p) => {
      const bot = sanitizeBot(p && p.bot);
      if (!bot) return;
      const snap = snapshots.get(desktopId);
      if (snap) {
        const i = snap.bots.findIndex((b) => b.id === bot.id);
        if (i >= 0) snap.bots[i] = bot; else if (snap.bots.length < LIMITS.MAX_CONFIGURED_BOTS) snap.bots.push(bot);
        snap.activeCount = snap.bots.filter((b) => b.status !== 'stopped').length;
      }
      io.to(phonesRoom(desktopId)).emit(EV.BOT_STATUS, { bot, activeCount: snap ? snap.activeCount : undefined });
    });

    const relayEntry = (event) => (p) => {
      if (!p || typeof p.botId !== 'string' || !ID_RE.test(p.botId)) return;
      const entry = sanitizeLog(p.entry);
      if (entry) io.to(phonesRoom(desktopId)).emit(event, { botId: p.botId, entry });
    };
    socket.on(EV.BOT_LOG, relayEntry(EV.BOT_LOG));
    socket.on(EV.BOT_CHAT, relayEntry(EV.BOT_CHAT));

    socket.on('disconnect', () => {
      if (desktops.get(desktopId) === socket) {
        desktops.delete(desktopId);
        io.to(phonesRoom(desktopId)).emit(EV.PRESENCE, { desktopOnline: false });
      }
    });
  }

  // ---- Phone -------------------------------------------------------------------------------
  function onPhone(socket) {
    const { desktopId, phoneId } = socket.data;
    socket.join(phonesRoom(desktopId));
    socket.join(phoneRoom(phoneId));
    store.touchPhone(phoneId).catch(noop);
    socket.emit(EV.PRESENCE, { desktopOnline: desktops.has(desktopId) });
    const snap = snapshots.get(desktopId);
    if (snap) socket.emit(EV.BOTS_SNAPSHOT, snap);
    pushPhonesOnline(desktopId);
    desktops.get(desktopId)?.emit(EV.PHONES_CHANGED);

    socket.on(EV.COMMAND, (payload, cb) => {
      const reply = ackOf(cb);
      const v = validateCommand(payload);
      if (!v.ok) return reply(v);
      const desk = desktops.get(desktopId);
      if (!desk) return reply(fail('DESKTOP_OFFLINE', 'Your PC is offline'));
      return desk.timeout(COMMAND_TIMEOUT_MS).emit(EV.COMMAND, v.value, (e, res) => {
        if (e) return reply(fail('TIMEOUT', 'The PC did not answer in time'));
        return reply(res && typeof res === 'object' ? res : fail('BAD_RESPONSE', 'Invalid response from PC'));
      });
    });

    socket.on('disconnect', () => { pushPhonesOnline(desktopId); desktops.get(desktopId)?.emit(EV.PHONES_CHANGED); });
  }

  // ---- API used by HTTP routes / hooks -----------------------------------------------------
  const gateway = {
    notifyPaired(desktopId, phone) {
      desktops.get(desktopId)?.emit(EV.PAIRING_COMPLETED, { phoneId: phone.id, name: phone.name });
      desktops.get(desktopId)?.emit(EV.PHONES_CHANGED);
    },
    revokePhone(desktopId, phoneId) {
      io.in(phoneRoom(phoneId)).emit(EV.REVOKED);
      io.in(phoneRoom(phoneId)).disconnectSockets(true);
      desktops.get(desktopId)?.emit(EV.PHONES_CHANGED);
    },
    isDesktopOnline: (id) => desktops.has(id),
  };
  return gateway;
}

module.exports = { attachGateway };
