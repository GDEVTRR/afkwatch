'use strict';
const { EV, ID_RE, validateCommand, sanitizeSnapshot, sanitizeBot, sanitizeLog, sanitizeScreenshot, fail } = require('./protocol');
const { createBucket } = require('./security');

const COMMAND_TIMEOUT_MS = 15000;
const noop = () => {};
const ackOf = (callback) => (typeof callback === 'function' ? callback : noop);
const phonesRoom = (desktopId) => `phones:${desktopId}`;
const phoneRoom = (phoneId) => `phone:${phoneId}`;

function attachGateway(io, { store, security, pairing }) {
  const desktops = new Map();
  const snapshots = new Map();
  const phonesOnline = (id) => io.sockets.adapter.rooms.get(phonesRoom(id))?.size || 0;
  const pushPhonesOnline = (id) => desktops.get(id)?.emit(EV.PRESENCE, { phonesOnline: phonesOnline(id) });

  io.use(async (socket, next) => {
    try {
      const auth = socket.handshake.auth || {};
      if (typeof auth.token !== 'string' || auth.token.length < 20 || auth.token.length > 128) return next(new Error('unauthorized'));
      if (auth.role === 'desktop') {
        if (typeof auth.deviceId !== 'string' || !/^[A-Za-z0-9_-]{8,64}$/.test(auth.deviceId)) return next(new Error('unauthorized'));
        const desktop = await store.getDesktop(auth.deviceId);
        if (!desktop || !security.safeEqual(desktop.tokenHash, security.hash(auth.token))) return next(new Error('unauthorized'));
        socket.data = { role: 'desktop', desktopId: desktop.id };
        return next();
      }
      if (auth.role === 'phone') {
        const phone = await store.getPhoneByTokenHash(security.hash(auth.token));
        if (!phone) return next(new Error('unauthorized'));
        socket.data = { role: 'phone', desktopId: phone.desktopId, phoneId: phone.id, phoneName: phone.name };
        return next();
      }
      return next(new Error('unauthorized'));
    } catch (error) {
      console.error('[auth] error:', error.message);
      return next(new Error('server_error'));
    }
  });

  io.on('connection', (socket) => {
    const bucket = socket.data.role === 'desktop' ? createBucket(150, 400) : createBucket(10, 30);
    socket.use((packet, next) => {
      if (bucket.take()) return next();
      const callback = packet[packet.length - 1];
      if (typeof callback === 'function') callback(fail('RATE_LIMITED', 'Too many events'));
      return undefined;
    });
    socket.on('error', (error) => console.warn('[socket] error:', error && error.message));
    if (socket.data.role === 'desktop') onDesktop(socket);
    else onPhone(socket);
  });

  function onDesktop(socket) {
    const { desktopId } = socket.data;
    const previous = desktops.get(desktopId);
    if (previous && previous.id !== socket.id) { previous.emit(EV.REPLACED); previous.disconnect(true); }
    desktops.set(desktopId, socket);
    socket.join(`desktop:${desktopId}`);
    io.to(phonesRoom(desktopId)).emit(EV.PRESENCE, { desktopOnline: true });
    socket.emit(EV.PRESENCE, { phonesOnline: phonesOnline(desktopId) });

    socket.on(EV.D_PAIRING_CREATE, async (_payload, callback) => {
      try { ackOf(callback)({ ok: true, data: await pairing.createCode(desktopId) }); }
      catch (error) { console.error('[pairing]', error.message); ackOf(callback)(fail('SERVER_ERROR', 'Could not create pairing code')); }
    });

    socket.on(EV.D_PHONES_LIST, async (_payload, callback) => {
      try {
        const list = await store.listPhones(desktopId);
        ackOf(callback)({ ok: true, data: { phones: list.map((phone) => ({
          id: phone.id, name: phone.name, createdAt: phone.createdAt, lastSeenAt: phone.lastSeenAt,
          online: Boolean(io.sockets.adapter.rooms.get(phoneRoom(phone.id))?.size),
        })) } });
      } catch { ackOf(callback)(fail('SERVER_ERROR', 'Could not list phones')); }
    });

    socket.on(EV.D_PHONES_REVOKE, async (payload, callback) => {
      try {
        if (!payload || typeof payload.phoneId !== 'string' || !ID_RE.test(payload.phoneId)) return ackOf(callback)(fail('BAD_REQUEST', 'Invalid phoneId'));
        const removed = await store.deletePhone(desktopId, payload.phoneId);
        if (!removed) return ackOf(callback)(fail('NOT_FOUND', 'Phone not found'));
        gateway.revokePhone(desktopId, payload.phoneId);
        return ackOf(callback)({ ok: true });
      } catch { return ackOf(callback)(fail('SERVER_ERROR', 'Could not revoke phone')); }
    });

    socket.on(EV.BOTS_SNAPSHOT, (payload) => {
      const snapshot = sanitizeSnapshot(payload);
      if (!snapshot) return;
      snapshots.set(desktopId, snapshot);
      io.to(phonesRoom(desktopId)).emit(EV.BOTS_SNAPSHOT, snapshot);
    });

    socket.on(EV.BOT_STATUS, (payload) => {
      const bot = sanitizeBot(payload && payload.bot);
      if (!bot) return;
      const snapshot = snapshots.get(desktopId);
      if (snapshot) {
        const index = snapshot.bots.findIndex((entry) => entry.id === bot.id);
        if (index >= 0) snapshot.bots[index] = bot;
        else snapshot.bots.push(bot);
        snapshot.activeCount = snapshot.bots.filter((entry) => entry.status !== 'stopped').length;
      }
      io.to(phonesRoom(desktopId)).emit(EV.BOT_STATUS, { bot, activeCount: snapshot ? snapshot.activeCount : undefined });
    });

    const relayEntry = (event) => (payload) => {
      if (!payload || typeof payload.botId !== 'string' || !ID_RE.test(payload.botId)) return;
      const entry = sanitizeLog(payload.entry);
      if (entry) io.to(phonesRoom(desktopId)).emit(event, { botId: payload.botId, entry });
    };
    socket.on(EV.BOT_LOG, relayEntry(EV.BOT_LOG));
    socket.on(EV.BOT_CHAT, relayEntry(EV.BOT_CHAT));

    // GUI snapshots are structured Mineflayer state. The cloud only relays them; it stores no screenshots.
    socket.on(EV.BOT_SCREENSHOT, (payload) => {
      const screenshot = sanitizeScreenshot(payload);
      if (screenshot) io.to(phonesRoom(desktopId)).emit(EV.BOT_SCREENSHOT, screenshot);
    });

    socket.on('disconnect', () => {
      if (desktops.get(desktopId) === socket) {
        desktops.delete(desktopId);
        io.to(phonesRoom(desktopId)).emit(EV.PRESENCE, { desktopOnline: false });
      }
    });
  }

  function onPhone(socket) {
    const { desktopId, phoneId } = socket.data;
    socket.join(phonesRoom(desktopId));
    socket.join(phoneRoom(phoneId));
    store.touchPhone(phoneId).catch(noop);
    socket.emit(EV.PRESENCE, { desktopOnline: desktops.has(desktopId) });
    const snapshot = snapshots.get(desktopId);
    if (snapshot) socket.emit(EV.BOTS_SNAPSHOT, snapshot);
    pushPhonesOnline(desktopId);
    desktops.get(desktopId)?.emit(EV.PHONES_CHANGED);

    socket.on(EV.COMMAND, (payload, callback) => {
      const reply = ackOf(callback);
      const validated = validateCommand(payload);
      if (!validated.ok) return reply(validated);
      const desktop = desktops.get(desktopId);
      if (!desktop) return reply(fail('DESKTOP_OFFLINE', 'Your PC is offline'));
      return desktop.timeout(COMMAND_TIMEOUT_MS).emit(EV.COMMAND, validated.value, (error, response) => {
        if (error) return reply(fail('TIMEOUT', 'The PC did not answer in time'));
        return reply(response && typeof response === 'object' ? response : fail('BAD_RESPONSE', 'Invalid response from PC'));
      });
    });

    socket.on('disconnect', () => { pushPhonesOnline(desktopId); desktops.get(desktopId)?.emit(EV.PHONES_CHANGED); });
  }

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
