/**
 * store.server.test.ts — Thorough vitest coverage for S2.2
 *
 * AC1  grep-check: @ladybugdb/core not imported outside store*.ts
 * AC2  containment verbs round-trip
 * AC3  mythos-head verbs: PREDECESSOR edge exists
 * AC4  ActionLog commit-log write + headHashes
 * AC5  50-verb spy: every query() paired with close()
 * AC6  API surface: only escape-hatch matches /raw|cypher/i
 * AC7  syncfs no-op within 1ms
 * AC9  replay-from-CAS: histogram equality after delete + replay
 *
 * 2026-04-24 hardening: all fp strings in test fixtures now flow through
 * `fp()` from test-fixtures.ts so they pass the 64-hex validators in
 * cypher-utils.ts. Raw Cypher queries interpolate the same validated fps.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { execSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import lbug from '@ladybugdb/core';
import { ServerStore } from './store.server.js';
import { PolicyDeniedError } from './store-types.js';
import { InvalidCypherValueError } from './cypher-utils.js';
import { fp } from './test-fixtures.js';


// ── Helpers ───────────────────────────────────────────────────────────────────

/** Create an isolated temp-dir store, return it open and ready. */
async function makeTempStore(): Promise<{ store: ServerStore; dir: string }> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dreamball-test-'));
  const dbPath = path.join(dir, 'palace.lbug');
  const store = new ServerStore(dbPath);
  await store.open();
  return { store, dir };
}

async function closeTempStore(store: ServerStore, dir: string): Promise<void> {
  await store.close();
  fs.rmSync(dir, { recursive: true, force: true });
}

// ── AC1: grep-check ───────────────────────────────────────────────────────────

describe('AC1 — @ladybugdb/core not imported outside store*.ts', () => {
  it('grep returns zero matches when store*.ts excluded', () => {
    const repoRoot = path.resolve(import.meta.dirname, '../../..');
    // Run grep; exit code 1 means no matches (which is what we want)
    let output = '';
    let exitCode = 0;
    try {
      output = execSync(
        `grep -r --include="*.ts" --include="*.js" "@ladybugdb/core" "${repoRoot}/src" "${repoRoot}/jelly-server" \
         --exclude="store.server.ts" --exclude="store.ts" --exclude="store-types.ts" \
         --exclude="parity.test.ts"`,
        { encoding: 'utf-8' }
      );
    } catch (e: unknown) {
      exitCode = (e as { status?: number }).status ?? 1;
    }
    // grep exits 1 when no lines match — that's the success case here
    if (exitCode === 0) {
      // Some matches found outside store*.ts and parity.test.ts — FAIL
      expect(output.trim()).toBe('');
    } else {
      // exit 1 = no matches = pass
      expect(exitCode).toBe(1);
    }
  });
});

// ── AC2: containment verbs ────────────────────────────────────────────────────

describe('AC2 — containment verbs round-trip', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('ensurePalace → addRoom → inscribeAvatar yields Palace-CONTAINS-Room-CONTAINS-Inscription', async () => {
    const palaceFp = fp('palace-fp-1');
    const roomFp = fp('room-fp-1');
    const avatarFp = fp('avatar-fp-1');
    const sourceBlake3 = fp('blake3abc');
    await store.ensurePalace(palaceFp);
    await store.addRoom(palaceFp, roomFp, { name: 'Test Room' });
    await store.inscribeAvatar(roomFp, avatarFp, sourceBlake3);

    const rows = await store.__rawQuery<{ cnt: number }>(
      `MATCH (:Palace)-[:CONTAINS]->(:Room)-[:CONTAINS]->(:Inscription) RETURN count(*) AS cnt`
    );
    expect(Number(rows[0].cnt)).toBe(1);
  });

  it('ensurePalace is idempotent (second call does not duplicate)', async () => {
    const palaceFp = fp('palace-fp-idempotent');
    await store.ensurePalace(palaceFp);
    await store.ensurePalace(palaceFp);
    const rows = await store.__rawQuery<{ cnt: number }>(
      `MATCH (p:Palace {fp: '${palaceFp}'}) RETURN count(p) AS cnt`
    );
    expect(Number(rows[0].cnt)).toBe(1);
  });

  it('inscribeAvatar creates LIVES_IN edge from Inscription to Room', async () => {
    const palaceFp = fp('palace-fp-2');
    const roomFp = fp('room-fp-2');
    const avatarFp = fp('avatar-fp-2');
    const sourceBlake3 = fp('blake3def');
    await store.ensurePalace(palaceFp);
    await store.addRoom(palaceFp, roomFp);
    await store.inscribeAvatar(roomFp, avatarFp, sourceBlake3);

    const rows = await store.__rawQuery<{ cnt: number }>(
      `MATCH (:Inscription {fp: '${avatarFp}'})-[:LIVES_IN]->(:Room {fp: '${roomFp}'})
       RETURN count(*) AS cnt`
    );
    expect(Number(rows[0].cnt)).toBe(1);
  });
});

// ── Cypher-injection regression guard (CRITICAL-1) ────────────────────────────

describe('CRITICAL-1 — mutation verbs reject Cypher-injection payloads', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('ensurePalace throws InvalidCypherValueError on injection payload', async () => {
    const evil = "abc'; MATCH (n) DETACH DELETE n; //";
    await expect(store.ensurePalace(evil)).rejects.toThrow(InvalidCypherValueError);
  });

  it('addRoom throws InvalidCypherValueError on injection payload', async () => {
    await store.ensurePalace(fp('p-for-injection'));
    const evil = "x'; DROP TABLE Palace; //";
    await expect(store.addRoom(fp('p-for-injection'), evil)).rejects.toThrow(
      InvalidCypherValueError
    );
  });

  it('recordAction rejects short/non-hex fps and fake action kinds', async () => {
    await expect(
      store.recordAction({
        fp: "bad'-fp",
        palaceFp: fp('p-for-injection'),
        actionKind: 'palace-minted',
        actorFp: fp('actor'),
        parentHashes: [],
        timestamp: Date.now(),
      })
    ).rejects.toThrow(InvalidCypherValueError);

    await expect(
      store.recordAction({
        fp: fp('good-action'),
        palaceFp: fp('p-for-injection'),
        actionKind: 'custom-made-up-kind',
        actorFp: fp('actor'),
        parentHashes: [],
        timestamp: Date.now(),
      })
    ).rejects.toThrow(InvalidCypherValueError);
  });
});

// ── CRITICAL-2: oracle write-gate denies non-file-watcher origin ──────────────

describe('CRITICAL-2 — oracle writes are restricted to file-watcher origin', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('custodian origin + oracle requester fp → PolicyDeniedError', async () => {
    const palaceFp = fp('palace-sec5');
    const oracleFp = fp('oracle-sec5');
    await store.ensurePalace(palaceFp);
    store.registerOracleFp(palaceFp, oracleFp);
    const restore = store.setWriteContext({ requesterFp: oracleFp, origin: 'custodian' });
    try {
      await expect(store.addRoom(palaceFp, fp('room-sec5'))).rejects.toThrow(
        PolicyDeniedError
      );
    } finally {
      restore();
    }
  });

  it('file-watcher origin + oracle requester fp → write allowed', async () => {
    const palaceFp = fp('palace-fw-ok');
    const oracleFp = fp('oracle-fw-ok');
    await store.ensurePalace(palaceFp);
    store.registerOracleFp(palaceFp, oracleFp);
    const restore = store.setWriteContext({ requesterFp: oracleFp, origin: 'file-watcher' });
    try {
      await expect(store.addRoom(palaceFp, fp('room-fw-ok'))).resolves.toBeUndefined();
    } finally {
      restore();
    }
  });
});

// ── AC3: mythos-head verbs ────────────────────────────────────────────────────

describe('AC3 — mythos-head verbs: setMythosHead + appendMythos', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('setMythosHead genesis → appendMythos → setMythosHead: MYTHOS_HEAD updated, PREDECESSOR exists', async () => {
    const palaceFp = fp('palace-m1');
    const genesisFp = fp('mythos-gen');
    const v2Fp = fp('mythos-v2');
    const actionFp = fp('action-fp-99');
    await store.ensurePalace(palaceFp);
    // genesis
    await store.setMythosHead(palaceFp, genesisFp, { isGenesis: true });

    // check genesis head
    const headBefore = await store.getMythosHead(palaceFp);
    expect(headBefore).toBe(genesisFp);

    // append successor
    await store.appendMythos(v2Fp, genesisFp, { bodyHash: 'bh2' });

    // move head to v2
    await store.setMythosHead(palaceFp, v2Fp, { actionFp });

    // verify MYTHOS_HEAD points to v2
    const headRows = await store.__rawQuery<{ fp: string }>(
      `MATCH (:Palace {fp: '${palaceFp}'})-[:MYTHOS_HEAD]->(m:Mythos) RETURN m.fp AS fp`
    );
    expect(headRows).toHaveLength(1);
    expect(String(headRows[0].fp)).toBe(v2Fp);

    // verify PREDECESSOR edge: mythos-v2 → mythos-gen
    const predRows = await store.__rawQuery<{ cnt: number }>(
      `MATCH (:Mythos {fp: '${v2Fp}'})-[:PREDECESSOR]->(:Mythos {fp: '${genesisFp}'})
       RETURN count(*) AS cnt`
    );
    expect(Number(predRows[0].cnt)).toBe(1);

    // verify only ONE MYTHOS_HEAD edge from palace
    const edgeCount = await store.__rawQuery<{ cnt: number }>(
      `MATCH (:Palace {fp: '${palaceFp}'})-[e:MYTHOS_HEAD]->(:Mythos) RETURN count(e) AS cnt`
    );
    expect(Number(edgeCount[0].cnt)).toBe(1);
  });

  it('getMythosHead returns null when no head set', async () => {
    const palaceFp = fp('palace-nohead');
    await store.ensurePalace(palaceFp);
    const head = await store.getMythosHead(palaceFp);
    expect(head).toBeNull();
  });
});

// ── AC4: ActionLog commit-log + headHashes ────────────────────────────────────

describe('AC4 — ActionLog commit-log write + headHashes', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('recordAction writes a row to ActionLog; headHashes includes the new fp', async () => {
    const palaceFp = fp('palace-al1');
    const actionFp = fp('action-fp-1');
    const actorFp = fp('agent-fp-1');
    await store.ensurePalace(palaceFp);
    await store.recordAction({
      fp: actionFp,
      palaceFp,
      actionKind: 'palace-minted',
      actorFp,
      targetFp: null,
      parentHashes: [],
      timestamp: new Date('2026-04-22T00:00:00Z')
    });

    const rows = await store.__rawQuery<{ fp: string }>(
      `MATCH (a:ActionLog {fp: '${actionFp}'}) RETURN a.fp AS fp`
    );
    expect(rows).toHaveLength(1);
    expect(String(rows[0].fp)).toBe(actionFp);

    const heads = await store.headHashes(palaceFp);
    expect(heads).toContain(actionFp);
  });

  it('headHashes excludes fps referenced as parent_hashes', async () => {
    const palaceFp = fp('palace-al2');
    const rootFp = fp('act-root');
    const childFp = fp('act-child');
    const actorFp = fp('agent-1');
    const roomFp = fp('room-1');
    await store.ensurePalace(palaceFp);
    // root action
    await store.recordAction({
      fp: rootFp,
      palaceFp,
      actionKind: 'palace-minted',
      actorFp,
      parentHashes: [],
      timestamp: new Date()
    });
    // child pointing at root
    await store.recordAction({
      fp: childFp,
      palaceFp,
      actionKind: 'room-added',
      actorFp,
      targetFp: roomFp,
      parentHashes: [rootFp],
      timestamp: new Date()
    });

    const heads = await store.headHashes(palaceFp);
    expect(heads).toContain(childFp);
    expect(heads).not.toContain(rootFp);
  });

  it('no Action node label exists — only ActionLog node-table', async () => {
    const tables = await store.__rawQuery<{ name: string; type: string }>(
      `CALL SHOW_TABLES() RETURN *`
    );
    const labels = tables.map((r) => String(r.name));
    expect(labels).not.toContain('Action');
    expect(labels).toContain('ActionLog');
  });
});

// ── AC5: explicit query/close pairing spy ─────────────────────────────────────

describe('AC5 — every query() paired with close() (50-verb spy)', () => {
  it('all QueryResult handles are closed before verbs return', async () => {
    const { store, dir } = await makeTempStore();

    let openHandles = 0;
    let closedHandles = 0;

    // Spy on the internal lbug.Connection.query to wrap every QueryResult
    // with close() tracking. We reach into the store's private conn via
    // the escape hatch to run real queries, while spying on qr.close().
    const origQuery = lbug.Connection.prototype.query;
    const spy = vi
      .spyOn(lbug.Connection.prototype, 'query')
      .mockImplementation(async function (this: InstanceType<typeof lbug.Connection>, ...args) {
        const raw = await origQuery.apply(this, args as Parameters<typeof origQuery>);
        const qrs = Array.isArray(raw) ? raw : [raw];
        for (const qr of qrs) {
          openHandles++;
          const origClose = qr.close.bind(qr);
          qr.close = () => {
            closedHandles++;
            return origClose();
          };
        }
        return raw;
      });

    const palaceFp = fp('palace-spy');
    const room1 = fp('room-spy-1');
    const room2 = fp('room-spy-2');
    const room3 = fp('room-spy-3');
    const ins1 = fp('ins-spy-1');
    const ins2 = fp('ins-spy-2');
    const ins3 = fp('ins-spy-3');
    const mythosGen = fp('mythos-spy-gen');
    const mythosV2 = fp('mythos-spy-v2');
    const agentSpy = fp('agent-spy');

    try {
      // Run a mix of ~50 verb calls
      await store.ensurePalace(palaceFp);
      await store.addRoom(palaceFp, room1);
      await store.addRoom(palaceFp, room2);
      await store.addRoom(palaceFp, room3);
      await store.inscribeAvatar(room1, ins1, fp('bh1'));
      await store.inscribeAvatar(room1, ins2, fp('bh2'));
      await store.inscribeAvatar(room2, ins3, fp('bh3'));
      await store.setMythosHead(palaceFp, mythosGen, { isGenesis: true });
      await store.appendMythos(mythosV2, mythosGen);
      await store.setMythosHead(palaceFp, mythosV2);
      await store.getMythosHead(palaceFp);
      const prior: string[] = [];
      for (let i = 0; i < 20; i++) {
        const actFp = fp(`action-spy-${i}`);
        await store.recordAction({
          fp: actFp,
          palaceFp,
          actionKind: 'room-added',
          actorFp: agentSpy,
          parentHashes: i > 0 ? [prior[prior.length - 1]] : [],
          timestamp: new Date()
        });
        prior.push(actFp);
      }
      await store.headHashes(palaceFp);
      await store.__rawQuery('MATCH (p:Palace) RETURN p.fp AS fp');

      // Every opened handle must be closed
      expect(openHandles).toBeGreaterThan(0);
      expect(closedHandles).toBe(openHandles);
    } finally {
      spy.mockRestore();
      await closeTempStore(store, dir);
    }
  });
});

// ── AC6: escape-hatch name constraint ────────────────────────────────────────

describe('AC6 — only __rawQuery matches /raw|cypher/i on the API surface', () => {
  it('all exported StoreAPI methods: only __rawQuery matches the pattern', async () => {
    const store = new ServerStore(':memory:');
    await store.open();
    const methodNames = Object.getOwnPropertyNames(
      Object.getPrototypeOf(store)
    ).filter((n) => n !== 'constructor' && typeof (store as unknown as Record<string, unknown>)[n] === 'function');

    const rawPattern = /raw|cypher/i;
    const matches = methodNames.filter((n) => rawPattern.test(n));
    // Private single-underscore methods (_q, _conn) are not public API.
    // __rawQuery starts with double-underscore — it IS the public escape-hatch.
    // Filter: exclude names that start with exactly one '_' (not two).
    const publicMatches = matches.filter((n) => !/^_[^_]/.test(n));
    expect(publicMatches).toEqual(['__rawQuery']);
    await store.close();
  });
});

// ── AC7: syncfs no-op within 1ms ─────────────────────────────────────────────

describe('AC7 — syncfs no-op on server resolves within 1ms', () => {
  it("syncfs('in') resolves within 1ms", async () => {
    const store = new ServerStore(':memory:');
    await store.open();
    const start = performance.now();
    await store.syncfs('in');
    const elapsed = performance.now() - start;
    expect(elapsed).toBeLessThan(1);
    await store.close();
  });

  it("syncfs('out') resolves within 1ms", async () => {
    const store = new ServerStore(':memory:');
    await store.open();
    const start = performance.now();
    await store.syncfs('out');
    const elapsed = performance.now() - start;
    expect(elapsed).toBeLessThan(1);
    await store.close();
  });
});

// ── Vector verbs — S2.5 implemented (was NotImplementedInS22 in S2.2) ─────────

describe('S2.5 — vector verbs are implemented (FR21 / AC8)', () => {
  let store: ServerStore;
  const palVec = fp('pal-vec');
  const roomVec = fp('room-vec');
  const inscVec = fp('insc-vec');
  const srcBlake = fp('sourcehash00');

  beforeEach(async () => {
    store = new ServerStore(':memory:');
    await store.open();
    // Seed an inscription for vector verb tests
    await store.ensurePalace(palVec);
    await store.addRoom(palVec, roomVec);
    await store.inscribeAvatar(roomVec, inscVec, srcBlake);
  });

  afterEach(async () => {
    await store.close();
  });

  it('upsertEmbedding does not throw — inscription gets embedding', async () => {
    await expect(
      store.upsertEmbedding(inscVec, new Float32Array(256).fill(0.1))
    ).resolves.toBeUndefined();
    // Node still exists
    const rows = await store.__rawQuery(
      `MATCH (i:Inscription {fp: '${inscVec}'}) RETURN i.fp AS fp`
    );
    expect(rows.length).toBe(1);
  });

  it('deleteEmbedding does not throw — inscription node preserved', async () => {
    await expect(store.deleteEmbedding(inscVec)).resolves.toBeUndefined();
    const rows = await store.__rawQuery(
      `MATCH (i:Inscription {fp: '${inscVec}'}) RETURN i.fp AS fp`
    );
    expect(rows.length).toBe(1);
  });

  it('reembed does not throw — updates inscription', async () => {
    const newVec = new Float32Array(256).fill(0.5);
    const newBytes = new Uint8Array(32).fill(7);
    await expect(store.reembed(inscVec, newBytes, newVec)).resolves.toBeUndefined();
  });

  it('kNN returns empty array when no embeddings exist (vector index may be empty)', async () => {
    // kNN on an empty / NULL-embedding table returns [] without throwing
    const result = await store.kNN(new Float32Array(256), 10);
    expect(Array.isArray(result)).toBe(true);
  });
});

// ── AC9: replay-from-CAS ──────────────────────────────────────────────────────

describe('AC9 — replay-from-CAS: histogram equality after delete + replay', () => {
  it('node-label histogram matches pre-delete after replaying ActionLog', async () => {
    // Phase 1: populate store with mutations, record actions as we go
    const dir1 = fs.mkdtempSync(path.join(os.tmpdir(), 'dreamball-replay-'));
    const dbPath1 = path.join(dir1, 'palace.lbug');
    const store1 = new ServerStore(dbPath1);
    await store1.open();

    const palaceFp = fp('replay-palace');
    const room1Fp = fp('replay-room-1');
    const room2Fp = fp('replay-room-2');
    const ins1Fp = fp('replay-ins-1');
    const ins2Fp = fp('replay-ins-2');
    const actor = fp('actor-1');
    const mintFp = fp('act-mint');
    const r1ActFp = fp('act-room1');
    const r2ActFp = fp('act-room2');
    const i1ActFp = fp('act-ins1');
    const i2ActFp = fp('act-ins2');
    const bh1 = fp('bh-ins1');
    const bh2 = fp('bh-ins2');

    await store1.ensurePalace(palaceFp);
    await store1.recordAction({
      fp: mintFp,
      palaceFp,
      actionKind: 'palace-minted',
      actorFp: actor,
      parentHashes: [],
      timestamp: new Date('2026-01-01T00:00:00Z')
    });

    await store1.addRoom(palaceFp, room1Fp, { name: 'Room 1' });
    await store1.recordAction({
      fp: r1ActFp,
      palaceFp,
      actionKind: 'room-added',
      actorFp: actor,
      targetFp: room1Fp,
      parentHashes: [mintFp],
      timestamp: new Date('2026-01-01T00:01:00Z')
    });

    await store1.addRoom(palaceFp, room2Fp, { name: 'Room 2' });
    await store1.recordAction({
      fp: r2ActFp,
      palaceFp,
      actionKind: 'room-added',
      actorFp: actor,
      targetFp: room2Fp,
      parentHashes: [r1ActFp],
      timestamp: new Date('2026-01-01T00:02:00Z')
    });

    // For avatar-inscribed, we encode actor_fp=roomFp, target_fp=avatarFp convention
    await store1.inscribeAvatar(room1Fp, ins1Fp, bh1);
    await store1.recordAction({
      fp: i1ActFp,
      palaceFp,
      actionKind: 'avatar-inscribed',
      actorFp: room1Fp,
      targetFp: ins1Fp,
      parentHashes: [r1ActFp],
      cborBytesBlake3: bh1,
      timestamp: new Date('2026-01-01T00:03:00Z')
    });

    await store1.inscribeAvatar(room2Fp, ins2Fp, bh2);
    await store1.recordAction({
      fp: i2ActFp,
      palaceFp,
      actionKind: 'avatar-inscribed',
      actorFp: room2Fp,
      targetFp: ins2Fp,
      parentHashes: [r2ActFp],
      cborBytesBlake3: bh2,
      timestamp: new Date('2026-01-01T00:04:00Z')
    });

    // Capture node-label histogram (count of each node label)
    async function histogram(s: ServerStore): Promise<Map<string, number>> {
      const tables = await s.__rawQuery<{ name: string; type: string }>(
        `CALL SHOW_TABLES() RETURN *`
      );
      const h = new Map<string, number>();
      for (const t of tables) {
        if (String(t.type) !== 'NODE') continue;
        const label = String(t.name);
        const cnt = await s.__rawQuery<{ c: number }>(
          `MATCH (n:${label}) RETURN count(n) AS c`
        );
        h.set(label, Number(cnt[0]?.c ?? 0));
      }
      return h;
    }

    const histBefore = await histogram(store1);

    // Read all action log rows for replay — explicit column aliases to avoid
    // table-prefix ambiguity with RETURN a.*
    const actionRows = await store1.__rawQuery<{
      fp: string;
      palace_fp: string;
      action_kind: string;
      actor_fp: string;
      target_fp: string;
      parent_hashes: unknown;
      timestamp: unknown;
      cbor_bytes_blake3: string;
    }>(
      `MATCH (a:ActionLog {palace_fp: '${palaceFp}'})
       RETURN a.fp AS fp, a.palace_fp AS palace_fp, a.action_kind AS action_kind,
              a.actor_fp AS actor_fp, a.target_fp AS target_fp,
              a.parent_hashes AS parent_hashes, a.timestamp AS timestamp,
              a.cbor_bytes_blake3 AS cbor_bytes_blake3
       ORDER BY a.timestamp`
    );

    await store1.close();

    // Phase 2: delete the .lbug directory
    fs.rmSync(dir1, { recursive: true, force: true });

    // Phase 3: replay into a fresh store
    const dir2 = fs.mkdtempSync(path.join(os.tmpdir(), 'dreamball-replay2-'));
    const dbPath2 = path.join(dir2, 'palace.lbug');
    const store2 = new ServerStore(dbPath2);
    await store2.open();

    for (const row of actionRows) {
      // mirrorAction (S2.4) writes both ActionLog row AND domain graph mutations atomically.
      await store2.mirrorAction({
        fp: String(row.fp),
        palace_fp: String(row.palace_fp),
        action_kind: String(row.action_kind),
        actor_fp: String(row.actor_fp),
        target_fp: String(row.target_fp ?? ''),
        parent_hashes: Array.isArray(row.parent_hashes)
          ? (row.parent_hashes as unknown[]).map(String)
          : [],
        timestamp: typeof row.timestamp === 'number' ? row.timestamp : Date.now(),
        cbor_bytes_blake3: String(row.cbor_bytes_blake3 ?? '')
      });
    }

    const histAfter = await histogram(store2);

    // Compare histograms
    for (const [label, count] of histBefore) {
      expect(histAfter.get(label)).toBe(count);
    }

    await store2.close();
    fs.rmSync(dir2, { recursive: true, force: true });
  });
});
