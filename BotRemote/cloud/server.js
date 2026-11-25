'use strict';
const http = require('http');
const express = require('express');
const { Server } = require('socket.io');
const { loadConfig } = require('./services/config');
const { createStore } = require('./services/store');
const { createSecurity } = require('./services/security');
const { createPairingService } = require('./services/pairing');
const gatewayModule = require('./services/gateway');
const { createApiRouter } = require('./routes/api');
const mw = require('./middleware/security');

/** Build the app. Exported so tests can start it on an ephemeral port with an in-memory store. */
function createApp(cfg, store) {
  const security = createSecurity(cfg.pepper);
  const pairing = createPairingService({ store, security });

  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', cfg.trustProxy);
  app.get('/healthz', (_req, res) => res.json({ ok: true }));
  app.use(mw.requireHttps(cfg.isProd));
  app.use(mw.helmet());

  const server = http.createServer(app);
  const io = new Server(server, {
    transports: ['websocket', 'polling'],
    maxHttpBufferSize: 256 * 1024,   // payload cap per message
    pingInterval: 25000,             // engine-level heartbeat (connection monitoring)
    pingTimeout: 30000,
    connectTimeout: 20000,
    serveClient: false,
    cors: { origin: false },         // native clients only; no browser origins allowed
  });

  const gateway = gatewayModule.attachGateway(io, { store, security, pairing });

  app.use('/api', createApiRouter({ cfg, store, security, pairing, gateway }));
  app.use((_req, res) => res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Not found' } }));
  // eslint-disable-next-line no-unused-vars
  app.use((e, _req, res, _next) => {
    if (e && e.type === 'entity.parse.failed') return res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'Invalid JSON' } });
    if (e && e.type === 'entity.too.large') return res.status(413).json({ error: { code: 'TOO_LARGE', message: 'Payload too large' } });
    console.error('[http] unhandled:', e && e.message);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Internal error' } });
  });

  return { app, server, io, gateway };
}

async function main() {
  const cfg = loadConfig();
  const store = createStore(cfg);
  await store.init();
  const { server, io } = createApp(cfg, store);
  server.listen(cfg.port, () => console.log(`[cloud] listening on :${cfg.port} (store=${store.kind}, prod=${cfg.isProd})`));

  let closing = false;
  const shutdown = (sig) => {
    if (closing) return; closing = true;
    console.log(`[cloud] ${sig} received, shutting down`);
    io.close(() => server.close(() => store.close().finally(() => process.exit(0))));
    setTimeout(() => process.exit(0), 8000).unref();
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

if (require.main === module) {
  main().catch((e) => { console.error('[cloud] fatal:', e.message); process.exit(1); });
}
module.exports = { createApp };
