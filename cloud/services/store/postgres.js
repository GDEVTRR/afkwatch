
'use strict';

const { Pool } = require('pg');

const SCHEMA = `
CREATE TABLE IF NOT EXISTS desktops (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  token_hash  TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pairing_codes (
  code_hash   TEXT PRIMARY KEY,
  desktop_id  TEXT NOT NULL REFERENCES desktops(id) ON DELETE CASCADE,
  expires_at  TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS pairing_codes_desktop_idx
ON pairing_codes(desktop_id);

CREATE TABLE IF NOT EXISTS phones (
  id           TEXT PRIMARY KEY,
  desktop_id   TEXT NOT NULL REFERENCES desktops(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  token_hash   TEXT NOT NULL UNIQUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS phones_desktop_idx
ON phones(desktop_id);
`;

const ms = (d) => (d ? new Date(d).getTime() : null);

const phoneRow = (r) => r && ({
  id: r.id,
  desktopId: r.desktop_id,
  name: r.name,
  tokenHash: r.token_hash,
  createdAt: ms(r.created_at),
  lastSeenAt: ms(r.last_seen_at),
});

function createPostgresStore({ url, ssl, pool: injected } = {}) {
  if (!injected && !url) {
    throw new Error('DATABASE_URL is required for PostgreSQL');
  }

  const pool = injected || new Pool({
    connectionString: url,
    max: 5,
    idleTimeoutMillis: 30000,
    ssl: {
      rejectUnauthorized: false,
    },
  });

  pool.on('error', (e) => {
    console.error('[pg] idle client error:', e.message);
  });

  return {
    kind: 'postgres',

    async init() {
      await pool.query(SCHEMA);
    },

    async close() {
      if (!injected) {
        await pool.end();
      }
    },

    async createDesktop(d) {
      await pool.query(
        'INSERT INTO desktops (id, name, token_hash) VALUES ($1,$2,$3)',
        [d.id, d.name, d.tokenHash]
      );
    },

    async getDesktop(id) {
      const { rows } = await pool.query(
        'SELECT id, name, token_hash FROM desktops WHERE id=$1',
        [id]
      );

      return rows[0]
        ? {
            id: rows[0].id,
            name: rows[0].name,
            tokenHash: rows[0].token_hash,
          }
        : null;
    },

    async replacePairing(desktopId, codeHash, expiresAt) {
      const c = await pool.connect();

      try {
        await c.query('BEGIN');

        await c.query(
          'DELETE FROM pairing_codes WHERE desktop_id=$1 OR expires_at < now()',
          [desktopId]
        );

        await c.query(
          'INSERT INTO pairing_codes (code_hash, desktop_id, expires_at) VALUES ($1,$2,$3)',
          [codeHash, desktopId, new Date(expiresAt)]
        );

        await c.query('COMMIT');
      } catch (e) {
        await c.query('ROLLBACK').catch(() => {});
        throw e;
      } finally {
        c.release();
      }
    },

    /** Atomic single-use: each pairing code can only be consumed once. */
    async consumePairing(codeHash) {
      const { rows } = await pool.query(
        'DELETE FROM pairing_codes WHERE code_hash=$1 RETURNING desktop_id, expires_at',
        [codeHash]
      );

      return rows[0]
        ? {
            desktopId: rows[0].desktop_id,
            expiresAt: ms(rows[0].expires_at),
          }
        : null;
    },

    async countPhones(desktopId) {
      const { rows } = await pool.query(
        'SELECT count(*)::int AS n FROM phones WHERE desktop_id=$1',
        [desktopId]
      );

      return rows[0].n;
    },

    async createPhone(p) {
      await pool.query(
        'INSERT INTO phones (id, desktop_id, name, token_hash) VALUES ($1,$2,$3,$4)',
        [p.id, p.desktopId, p.name, p.tokenHash]
      );
    },

    async getPhoneByTokenHash(h) {
      const { rows } = await pool.query(
        'SELECT * FROM phones WHERE token_hash=$1',
        [h]
      );

      return phoneRow(rows[0]) || null;
    },

    async touchPhone(id) {
      await pool.query(
        'UPDATE phones SET last_seen_at=now() WHERE id=$1',
        [id]
      );
    },

    async listPhones(desktopId) {
      const { rows } = await pool.query(
        'SELECT * FROM phones WHERE desktop_id=$1 ORDER BY created_at',
        [desktopId]
      );

      return rows.map(phoneRow);
    },

    async deletePhone(desktopId, phoneId) {
      const r = await pool.query(
        'DELETE FROM phones WHERE id=$1 AND desktop_id=$2',
        [phoneId, desktopId]
      );

      return r.rowCount > 0;
    },
  };
}

module.exports = { createPostgresStore };
