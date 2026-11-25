'use strict';
const { createMemoryStore } = require('./memory');
const { createPostgresStore } = require('./postgres');

function createStore(cfg) {
  if (cfg.databaseUrl) return createPostgresStore({ url: cfg.databaseUrl, ssl: cfg.databaseSsl });
  console.warn('[store] DATABASE_URL not set: using NON-PERSISTENT in-memory store (development only).');
  return createMemoryStore();
}
module.exports = { createStore };
