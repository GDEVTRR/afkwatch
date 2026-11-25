'use strict';
/* Exercises the Postgres store against pg-mem (in-process Postgres emulator). Requires `npm i --no-save pg-mem`. */
const assert = require('assert');
const { newDb } = require('pg-mem');
const { createPostgresStore } = require('../services/store/postgres');

(async () => {
  const { Pool } = newDb().adapters.createPg();
  const store = createPostgresStore({ pool: new Pool() });
  await store.init();
  await store.createDesktop({ id: 'dsk_1', name: 'PC', tokenHash: 'h1' });
  assert.strictEqual((await store.getDesktop('dsk_1')).tokenHash, 'h1');
  await store.replacePairing('dsk_1', 'c1', Date.now() + 60000);
  await store.replacePairing('dsk_1', 'c2', Date.now() + 60000); // replaces c1
  assert.strictEqual(await store.consumePairing('c1'), null);
  const rec = await store.consumePairing('c2');
  assert.strictEqual(rec.desktopId, 'dsk_1'); assert.ok(rec.expiresAt > Date.now());
  assert.strictEqual(await store.consumePairing('c2'), null); // single use
  await store.createPhone({ id: 'ph_1', desktopId: 'dsk_1', name: 'iPhone', tokenHash: 'ph' });
  assert.strictEqual(await store.countPhones('dsk_1'), 1);
  assert.strictEqual((await store.getPhoneByTokenHash('ph')).id, 'ph_1');
  await store.touchPhone('ph_1');
  assert.ok((await store.listPhones('dsk_1'))[0].lastSeenAt > 0);
  assert.strictEqual(await store.deletePhone('other', 'ph_1'), false);
  assert.strictEqual(await store.deletePhone('dsk_1', 'ph_1'), true);
  console.log('POSTGRES STORE TESTS PASSED');
})().catch((e) => { console.error('FAILED', e); process.exit(1); });
