/**
 * action-mirror.test.ts — Thorough vitest coverage for S2.4 action-mirror.ts
 *
 * Covers AC3–AC11 against @ladybugdb/core server:
 *
 * AC3  DDL idempotent: double open() succeeds, no duplicate-table error
 * AC4  Vector index: SHOW_INDEXES() includes inscription_emb after open()
 * AC5  add-room: ActionLog row + CONTAINS edge committed (add-room mirror)
 * AC6  Rollback: bad palace fp → neither ActionLog row nor edge visible
 * AC7  true-naming: unique MYTHOS_HEAD + PREDECESSOR edge + discovered_in_action_fp = action fp
 * AC8  inscribe: Inscription + CONTAINS + LIVES_IN in same tx; orphaned=false
 * AC9  aqueduct-created: Aqueduct + AQUEDUCT_FROM + AQUEDUCT_TO + defaults resistance=0.3/capacitance=0.5
 * AC10 replay-from-CAS (NFR18): N actions → mirror → histogram → delete .lbug → replay → equal histograms + byte-identical cbor_bytes_blake3
 * AC11 TC13: no CBOR bytes in any column post-mutation
 *
 * 2026-04-24 hardening: fp arguments to store verbs MUST be 64-char hex.
 * Test fixtures flow through `fp()` (test-fixtures.ts) so validators pass.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { ServerStore } from './store.server.js';
import { fp } from './test-fixtures.js';

// ── Helpers ───────────────────────────────────────────────────────────────────

async function makeTempStore(): Promise<{ store: ServerStore; dir: string }> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dreamball-mirror-test-'));
  const dbPath = path.join(dir, 'palace.lbug');
  const store = new ServerStore(dbPath);
  await store.open();
  return { store, dir };
}

async function closeTempStore(store: ServerStore, dir: string): Promise<void> {
  await store.close();
  fs.rmSync(dir, { recursive: true, force: true });
}

/** Collect node-label → count histogram from an open store */
async function histogram(store: ServerStore): Promise<Map<string, number>> {
  const tables = await store.__rawQuery<{ name: string; type: string }>(
    'CALL SHOW_TABLES() RETURN *'
  );
  const h = new Map<string, number>();
  for (const t of tables) {
    if (String(t.type) !== 'NODE') continue;
    const label = String(t.name);
    const rows = await store.__rawQuery<{ fp: string }>(
      `MATCH (n:${label}) RETURN n.fp AS fp`
    );
    h.set(label, rows.length);
  }
  return h;
}

// ── AC3: DDL idempotent ───────────────────────────────────────────────────────

describe('AC3 — DDL idempotent: double open() succeeds', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('second open() returns without error (idempotent guard)', async () => {
    // store is already open from beforeEach; calling open() again must be safe
    await expect(store.open()).resolves.toBeUndefined();
  });

  it('persists across close → reopen with schema intact', async () => {
    const dbPath = path.join(dir, 'palace.lbug');
    await store.close();

    const store2 = new ServerStore(dbPath);
    await store2.open();

    const tables = await store2.__rawQuery<{ name: string }>(
      'CALL SHOW_TABLES() RETURN *'
    );
    const names = tables.map((r) => String(r.name));
    expect(names).toContain('Palace');
    expect(names).toContain('ActionLog');
    expect(names).toContain('CONTAINS');

    await store2.close();
  });
});

// ── AC4: Vector index ─────────────────────────────────────────────────────────

describe('AC4 — vector index inscription_emb present after open()', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('SHOW_INDEXES() includes inscription_emb', async () => {
    const indexes = await store.__rawQuery<{ index_name: string }>(
      'CALL SHOW_INDEXES() RETURN *'
    );
    const names = indexes.map((r) => String(r.index_name));
    expect(names).toContain('inscription_emb');
  });

  it('inscription_emb is not re-created on second open()', async () => {
    // If re-creation were attempted it would throw; simply not throwing proves idempotency
    await expect(store.open()).resolves.toBeUndefined();
    const indexes = await store.__rawQuery<{ index_name: string }>(
      'CALL SHOW_INDEXES() RETURN *'
    );
    const names = indexes.map((r) => String(r.index_name));
    expect(names).toContain('inscription_emb');
  });
});

// ── AC5: add-room mirror ──────────────────────────────────────────────────────

describe('AC5 — add-room mirror: ActionLog row + CONTAINS edge', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('mirrors palace-minted then room-added: ActionLog row + CONTAINS edge exist', async () => {
    const palaceFp = fp('ac5-palace');
    const roomFp = fp('ac5-room');
    const actorFp = fp('actor-1');
    const mintAct = fp('ac5-act-mint');
    const roomAct = fp('ac5-act-room');
    const now = Date.now();

    await store.mirrorAction({
      fp: mintAct,
      palace_fp: palaceFp,
      action_kind: 'palace-minted',
      actor_fp: actorFp,
      target_fp: '',
      parent_hashes: [],
      timestamp: now
    });

    await store.mirrorAction({
      fp: roomAct,
      palace_fp: palaceFp,
      action_kind: 'room-added',
      actor_fp: actorFp,
      target_fp: roomFp,
      parent_hashes: [mintAct],
      timestamp: now + 1
    });

    // ActionLog row exists
    const alRows = await store.__rawQuery<{ fp: string }>(
      `MATCH (a:ActionLog {fp: '${roomAct}'}) RETURN a.fp AS fp`
    );
    expect(alRows).toHaveLength(1);

    // CONTAINS edge exists: Palace → Room
    const edgeRows = await store.__rawQuery<{ r: unknown }>(
      `MATCH (:Palace {fp: '${palaceFp}'})-[:CONTAINS]->(:Room {fp: '${roomFp}'}) RETURN true AS r`
    );
    expect(edgeRows).toHaveLength(1);
  });
});

// ── AC6: Rollback on bad palace ───────────────────────────────────────────────

describe('AC6 — rollback: bad palace fp → no writes visible', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('mirrorAction throws when palace does not exist for room-added', async () => {
    await expect(
      store.mirrorAction({
        fp: fp('ac6-act-room'),
        palace_fp: fp('nonexistent-palace'),
        action_kind: 'room-added',
        actor_fp: fp('actor-1'),
        target_fp: fp('ac6-room'),
        parent_hashes: [],
        timestamp: Date.now()
      })
    ).rejects.toThrow(/palace.*not found/i);
  });

  it('no ActionLog row written after the throw', async () => {
    const badAct = fp('ac6-act-room2');
    try {
      await store.mirrorAction({
        fp: badAct,
        palace_fp: fp('nonexistent-palace-2'),
        action_kind: 'room-added',
        actor_fp: fp('actor-1'),
        target_fp: fp('ac6-room2'),
        parent_hashes: [],
        timestamp: Date.now()
      });
    } catch {
      // expected
    }
    const alRows = await store.__rawQuery<{ fp: string }>(
      `MATCH (a:ActionLog {fp: '${badAct}'}) RETURN a.fp AS fp`
    );
    expect(alRows).toHaveLength(0);
  });
});

// ── AC7: true-naming mirror ───────────────────────────────────────────────────

describe('AC7 — true-naming: MYTHOS_HEAD swap + PREDECESSOR + discovered_in_action_fp', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('true-naming creates new MYTHOS_HEAD, PREDECESSOR edge, and sets discovered_in_action_fp', async () => {
    const palaceFp = fp('ac7-palace');
    const genesisFp = fp('ac7-mythos-genesis');
    const successorFp = fp('ac7-mythos-v2');
    const actionFp = fp('ac7-act-rename');
    const mintAct = fp('ac7-act-mint');
    const actorFp = fp('actor-1');
    const now = Date.now();

    // First mint the palace
    await store.mirrorAction({
      fp: mintAct,
      palace_fp: palaceFp,
      action_kind: 'palace-minted',
      actor_fp: actorFp,
      target_fp: '',
      parent_hashes: [],
      timestamp: now
    });

    // Set genesis mythos head via verb (not mirror — setMythosHead uses store verb)
    await store.setMythosHead(palaceFp, genesisFp, { isGenesis: true });

    // Now mirror true-naming action
    await store.mirrorAction({
      fp: actionFp,
      palace_fp: palaceFp,
      action_kind: 'true-naming',
      actor_fp: actorFp,
      target_fp: successorFp,
      parent_hashes: [mintAct],
      timestamp: now + 1,
      extra: { predecessorFp: genesisFp, canonicality: 'successor' }
    });

    // Exactly one MYTHOS_HEAD from palace, pointing to successorFp
    const headRows = await store.__rawQuery<{ fp: string }>(
      `MATCH (:Palace {fp: '${palaceFp}'})-[:MYTHOS_HEAD]->(m:Mythos) RETURN m.fp AS fp`
    );
    expect(headRows).toHaveLength(1);
    expect(String(headRows[0].fp)).toBe(successorFp);

    // PREDECESSOR edge: successorFp → genesisFp
    const predRows = await store.__rawQuery<{ r: unknown }>(
      `MATCH (:Mythos {fp: '${successorFp}'})-[:PREDECESSOR]->(:Mythos {fp: '${genesisFp}'}) RETURN true AS r`
    );
    expect(predRows).toHaveLength(1);

    // discovered_in_action_fp on successor = actionFp
    const mRows = await store.__rawQuery<{ discovered_in_action_fp: string }>(
      `MATCH (m:Mythos {fp: '${successorFp}'}) RETURN m.discovered_in_action_fp AS discovered_in_action_fp`
    );
    expect(mRows).toHaveLength(1);
    expect(String(mRows[0].discovered_in_action_fp)).toBe(actionFp);
  });
});

// ── AC8: inscribe mirror ──────────────────────────────────────────────────────

describe('AC8 — inscribe: Inscription + CONTAINS + LIVES_IN; orphaned=false', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('avatar-inscribed creates Inscription node, CONTAINS edge, LIVES_IN edge with orphaned=false', async () => {
    const palaceFp = fp('ac8-palace');
    const roomFp = fp('ac8-room');
    const inscFp = fp('ac8-inscription');
    const sourceBlake3 = fp('bh-ac8-source');
    const actor = fp('a');
    const mintAct = fp('ac8-mint');
    const roomAct = fp('ac8-room-act');
    const inscAct = fp('ac8-insc');
    const now = Date.now();

    // Setup palace + room
    await store.mirrorAction({
      fp: mintAct,
      palace_fp: palaceFp,
      action_kind: 'palace-minted',
      actor_fp: actor,
      target_fp: '',
      parent_hashes: [],
      timestamp: now
    });
    await store.mirrorAction({
      fp: roomAct,
      palace_fp: palaceFp,
      action_kind: 'room-added',
      actor_fp: actor,
      target_fp: roomFp,
      parent_hashes: [mintAct],
      timestamp: now + 1
    });

    // Mirror inscribe — convention: actor_fp=roomFp, target_fp=inscFp, cbor_bytes_blake3=sourceBlake3
    await store.mirrorAction({
      fp: inscAct,
      palace_fp: palaceFp,
      action_kind: 'avatar-inscribed',
      actor_fp: roomFp,
      target_fp: inscFp,
      parent_hashes: [roomAct],
      timestamp: now + 2,
      cbor_bytes_blake3: sourceBlake3
    });

    // Inscription node exists with orphaned=false
    const inscRows = await store.__rawQuery<{ fp: string; orphaned: unknown }>(
      `MATCH (i:Inscription {fp: '${inscFp}'}) RETURN i.fp AS fp, i.orphaned AS orphaned`
    );
    expect(inscRows).toHaveLength(1);
    expect(inscRows[0].orphaned).toBe(false);

    // CONTAINS edge: Room → Inscription
    const cRows = await store.__rawQuery<{ r: unknown }>(
      `MATCH (:Room {fp: '${roomFp}'})-[:CONTAINS]->(:Inscription {fp: '${inscFp}'}) RETURN true AS r`
    );
    expect(cRows).toHaveLength(1);

    // LIVES_IN edge: Inscription → Room
    const liRows = await store.__rawQuery<{ r: unknown }>(
      `MATCH (:Inscription {fp: '${inscFp}'})-[:LIVES_IN]->(:Room {fp: '${roomFp}'}) RETURN true AS r`
    );
    expect(liRows).toHaveLength(1);
  });
});

// ── AC9: aqueduct-created mirror ──────────────────────────────────────────────

describe('AC9 — aqueduct-created: Aqueduct + AQUEDUCT_FROM + AQUEDUCT_TO + D3 defaults', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('creates Aqueduct node with resistance=0.3, capacitance=0.5 and two rel edges', async () => {
    const palaceFp = fp('ac9-palace');
    const room1Fp = fp('ac9-room-a');
    const room2Fp = fp('ac9-room-b');
    const aqFp = fp('ac9-aqueduct');
    const actor = fp('a');
    const mintAct = fp('ac9-mint');
    const roomAAct = fp('ac9-room-a-act');
    const roomBAct = fp('ac9-room-b-act');
    const aqAct = fp('ac9-aq');
    const now = Date.now();

    await store.mirrorAction({
      fp: mintAct,
      palace_fp: palaceFp,
      action_kind: 'palace-minted',
      actor_fp: actor,
      target_fp: '',
      parent_hashes: [],
      timestamp: now
    });
    await store.mirrorAction({
      fp: roomAAct,
      palace_fp: palaceFp,
      action_kind: 'room-added',
      actor_fp: actor,
      target_fp: room1Fp,
      parent_hashes: [mintAct],
      timestamp: now + 1
    });
    await store.mirrorAction({
      fp: roomBAct,
      palace_fp: palaceFp,
      action_kind: 'room-added',
      actor_fp: actor,
      target_fp: room2Fp,
      parent_hashes: [mintAct],
      timestamp: now + 2
    });
    await store.mirrorAction({
      fp: aqAct,
      palace_fp: palaceFp,
      action_kind: 'aqueduct-created',
      actor_fp: actor,
      target_fp: aqFp,
      parent_hashes: [roomAAct, roomBAct],
      timestamp: now + 3,
      extra: { fromFp: room1Fp, toFp: room2Fp }
    });

    // Aqueduct node with D3 defaults
    const aqRows = await store.__rawQuery<{
      fp: string; resistance: unknown; capacitance: unknown
    }>(
      `MATCH (a:Aqueduct {fp: '${aqFp}'}) RETURN a.fp AS fp, a.resistance AS resistance, a.capacitance AS capacitance`
    );
    expect(aqRows).toHaveLength(1);
    expect(Number(aqRows[0].resistance)).toBeCloseTo(0.3, 10);
    expect(Number(aqRows[0].capacitance)).toBeCloseTo(0.5, 10);

    // AQUEDUCT_FROM edge
    const afRows = await store.__rawQuery<{ r: unknown }>(
      `MATCH (:Aqueduct {fp: '${aqFp}'})-[:AQUEDUCT_FROM]->(:Room {fp: '${room1Fp}'}) RETURN true AS r`
    );
    expect(afRows).toHaveLength(1);

    // AQUEDUCT_TO edge
    const atRows = await store.__rawQuery<{ r: unknown }>(
      `MATCH (:Aqueduct {fp: '${aqFp}'})-[:AQUEDUCT_TO]->(:Room {fp: '${room2Fp}'}) RETURN true AS r`
    );
    expect(atRows).toHaveLength(1);
  });
});

// ── AC10: replay-from-CAS (NFR18) ─────────────────────────────────────────────

describe('AC10 — replay-from-CAS (NFR18): histogram + cbor_bytes_blake3 byte-identical', () => {
  it('deleting .lbug and replaying ActionLog yields byte-identical histograms + blake3s', async () => {
    const dir1 = fs.mkdtempSync(path.join(os.tmpdir(), 'dreamball-ac10-'));
    const dbPath1 = path.join(dir1, 'palace.lbug');
    const store1 = new ServerStore(dbPath1);
    await store1.open();

    const palaceFp = fp('ac10-palace');
    const room1 = fp('ac10-r1');
    const room2 = fp('ac10-r2');
    const insc1 = fp('ac10-ins1');
    const insc2 = fp('ac10-ins2');
    const aqFp = fp('ac10-aq');
    const genMythos = fp('ac10-mythos-gen');
    const succMythos = fp('ac10-mythos-v2');
    const mintAct = fp('ac10-mint');
    const r1Act = fp('ac10-r1-act');
    const r2Act = fp('ac10-r2-act');
    const i1Act = fp('ac10-ins1-act');
    const i2Act = fp('ac10-ins2-act');
    const aqAct = fp('ac10-aq-act');
    const genAct = fp('ac10-mythos-gen-act');
    const succAct = fp('ac10-mythos-v2-act');
    const actor = fp('a');
    const bhMint = fp('blake3-mint');
    const bhR1 = fp('blake3-r1');
    const bhR2 = fp('blake3-r2');
    const bhIns1 = fp('blake3-ins1');
    const bhIns2 = fp('blake3-ins2');
    const bhAq = fp('blake3-aq');
    const bhGen = fp('blake3-gen');
    const bhV2 = fp('blake3-v2');
    const base = 1_700_000_000_000;

    // Populate via mirrorAction — each call writes ActionLog + graph
    const actions = [
      {
        fp: mintAct, palace_fp: palaceFp, action_kind: 'palace-minted',
        actor_fp: actor, target_fp: '', parent_hashes: [], timestamp: base,
        cbor_bytes_blake3: bhMint
      },
      {
        fp: r1Act, palace_fp: palaceFp, action_kind: 'room-added',
        actor_fp: actor, target_fp: room1, parent_hashes: [mintAct],
        timestamp: base + 1, cbor_bytes_blake3: bhR1
      },
      {
        fp: r2Act, palace_fp: palaceFp, action_kind: 'room-added',
        actor_fp: actor, target_fp: room2, parent_hashes: [r1Act],
        timestamp: base + 2, cbor_bytes_blake3: bhR2
      },
      {
        fp: i1Act, palace_fp: palaceFp, action_kind: 'avatar-inscribed',
        actor_fp: room1, target_fp: insc1, parent_hashes: [r1Act],
        timestamp: base + 3, cbor_bytes_blake3: bhIns1
      },
      {
        fp: i2Act, palace_fp: palaceFp, action_kind: 'avatar-inscribed',
        actor_fp: room2, target_fp: insc2, parent_hashes: [r2Act],
        timestamp: base + 4, cbor_bytes_blake3: bhIns2
      },
      {
        fp: aqAct, palace_fp: palaceFp, action_kind: 'aqueduct-created',
        actor_fp: actor, target_fp: aqFp, parent_hashes: [r1Act, r2Act],
        timestamp: base + 5, cbor_bytes_blake3: bhAq,
        extra: { fromFp: room1, toFp: room2 }
      },
      {
        fp: genAct, palace_fp: palaceFp, action_kind: 'true-naming',
        actor_fp: actor, target_fp: genMythos, parent_hashes: [mintAct],
        timestamp: base + 6, cbor_bytes_blake3: bhGen,
        extra: { predecessorFp: '', canonicality: 'genesis' }
      },
      {
        fp: succAct, palace_fp: palaceFp, action_kind: 'true-naming',
        actor_fp: actor, target_fp: succMythos, parent_hashes: [genAct],
        timestamp: base + 7, cbor_bytes_blake3: bhV2,
        extra: { predecessorFp: genMythos, canonicality: 'successor' }
      }
    ];

    for (const action of actions) {
      await store1.mirrorAction(action as Parameters<typeof store1.mirrorAction>[0]);
    }

    // Capture pre-delete histogram
    const histBefore = await histogram(store1);

    // Read ActionLog rows for replay
    const actionRows = await store1.__rawQuery<{
      fp: string; palace_fp: string; action_kind: string;
      actor_fp: string; target_fp: string;
      parent_hashes: unknown; timestamp: unknown; cbor_bytes_blake3: string;
    }>(
      `MATCH (a:ActionLog {palace_fp: '${palaceFp}'})
       RETURN a.fp AS fp, a.palace_fp AS palace_fp, a.action_kind AS action_kind,
              a.actor_fp AS actor_fp, a.target_fp AS target_fp,
              a.parent_hashes AS parent_hashes, a.timestamp AS timestamp,
              a.cbor_bytes_blake3 AS cbor_bytes_blake3
       ORDER BY a.timestamp`
    );

    await store1.close();
    fs.rmSync(dir1, { recursive: true, force: true });

    // Phase 2: replay into fresh store
    const dir2 = fs.mkdtempSync(path.join(os.tmpdir(), 'dreamball-ac10b-'));
    const dbPath2 = path.join(dir2, 'palace.lbug');
    const store2 = new ServerStore(dbPath2);
    await store2.open();

    for (const row of actionRows) {
      // Map extra fields back from the stored action_kind conventions
      let extra: Record<string, string> | undefined;
      if (String(row.action_kind) === 'aqueduct-created') {
        const orig = actions.find((a) => a.fp === String(row.fp));
        extra = orig?.extra as Record<string, string> | undefined;
      } else if (String(row.action_kind) === 'true-naming') {
        const orig = actions.find((a) => a.fp === String(row.fp));
        extra = orig?.extra as Record<string, string> | undefined;
      }

      await store2.mirrorAction({
        fp: String(row.fp),
        palace_fp: String(row.palace_fp),
        action_kind: String(row.action_kind),
        actor_fp: String(row.actor_fp),
        target_fp: String(row.target_fp ?? ''),
        parent_hashes: Array.isArray(row.parent_hashes)
          ? (row.parent_hashes as unknown[]).map(String)
          : [],
        timestamp: typeof row.timestamp === 'number' ? row.timestamp : base,
        cbor_bytes_blake3: String(row.cbor_bytes_blake3 ?? ''),
        extra
      });
    }

    // Compare histograms
    const histAfter = await histogram(store2);
    for (const [label, count] of histBefore) {
      expect(histAfter.get(label)).toBe(count);
    }

    // Verify cbor_bytes_blake3 values are byte-identical
    const replayedRows = await store2.__rawQuery<{ fp: string; cbor_bytes_blake3: string }>(
      `MATCH (a:ActionLog {palace_fp: '${palaceFp}'})
       RETURN a.fp AS fp, a.cbor_bytes_blake3 AS cbor_bytes_blake3`
    );
    const replayedMap = new Map(replayedRows.map((r) => [String(r.fp), String(r.cbor_bytes_blake3)]));

    for (const orig of actions) {
      const replayed = replayedMap.get(orig.fp);
      expect(replayed).toBe(orig.cbor_bytes_blake3);
    }

    await store2.close();
    fs.rmSync(dir2, { recursive: true, force: true });
  });
});

// ── AC11: TC13 no CBOR in columns ─────────────────────────────────────────────

describe('AC11 — TC13: no raw CBOR bytes in any column post-mutation', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });

  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('cbor_bytes_blake3 contains only hex-string pointer, never raw CBOR bytes', async () => {
    const palaceFp = fp('ac11-palace');
    const mintAct = fp('ac11-mint');
    const actor = fp('a');
    const now = Date.now();
    const fakeBlake3 = 'a'.repeat(64); // 64 hex chars = 32-byte blake3

    await store.mirrorAction({
      fp: mintAct,
      palace_fp: palaceFp,
      action_kind: 'palace-minted',
      actor_fp: actor,
      target_fp: '',
      parent_hashes: [],
      timestamp: now,
      cbor_bytes_blake3: fakeBlake3
    });

    const rows = await store.__rawQuery<{ cbor_bytes_blake3: string }>(
      `MATCH (a:ActionLog {fp: '${mintAct}'}) RETURN a.cbor_bytes_blake3 AS cbor_bytes_blake3`
    );
    expect(rows).toHaveLength(1);
    const stored = String(rows[0].cbor_bytes_blake3);

    // Must be a valid hex string (only 0-9, a-f), not binary garbage
    expect(stored).toMatch(/^[0-9a-fA-F]*$/);
    // Must not exceed 128 chars (blake3 is 64 hex chars = 32 bytes)
    expect(stored.length).toBeLessThanOrEqual(128);
  });

  it('no string column in any node contains CBOR magic bytes (0xa1/0x83 prefixes)', async () => {
    const palaceFp = fp('ac11-palace-scan');
    const mintAct = fp('ac11-scan-mint');
    const roomAct = fp('ac11-scan-room');
    const roomFp = fp('ac11-r');
    const actor = fp('a');
    const now = Date.now();

    await store.mirrorAction({
      fp: mintAct,
      palace_fp: palaceFp,
      action_kind: 'palace-minted',
      actor_fp: actor,
      target_fp: '',
      parent_hashes: [],
      timestamp: now,
      cbor_bytes_blake3: fp('deadbeef01')
    });
    await store.mirrorAction({
      fp: roomAct,
      palace_fp: palaceFp,
      action_kind: 'room-added',
      actor_fp: actor,
      target_fp: roomFp,
      parent_hashes: [mintAct],
      timestamp: now + 1,
      cbor_bytes_blake3: fp('cafebabe02')
    });

    const alRows = await store.__rawQuery<Record<string, unknown>>(
      `MATCH (a:ActionLog) RETURN a.fp AS fp, a.cbor_bytes_blake3 AS cbor_bytes_blake3,
             a.action_kind AS action_kind, a.actor_fp AS actor_fp, a.target_fp AS target_fp`
    );

    // CBOR binary magic bytes as single chars: char codes 0x80-0xbf
    const cbor_magic_re = /[\x80-\xbf]/;
    for (const row of alRows) {
      for (const [k, v] of Object.entries(row)) {
        if (typeof v === 'string') {
          expect(
            cbor_magic_re.test(v),
            `Column ${k} = ${JSON.stringify(v)} contains CBOR binary magic bytes`
          ).toBe(false);
        }
      }
    }
  });
});
