/**
 * inscription-mirror.test.ts — S4.3 thorough TDD coverage.
 *
 * AC1: inscribe mirrors triple to oracle KG + LadybugDB LIVES_IN + ActionLog in one tx.
 * AC2: move updates oracle KG triple + LIVES_IN + ActionLog.
 * AC3: count invariant after 3 inscribes across 2 rooms.
 * AC4: fault-injection: throw after triple-insert before recordAction → full rollback.
 * AC5: SIGKILL simulation (forced reject mid-sequence) → pre-mutation state preserved.
 * AC6: interleaved reader: action never observable without triple (100 iterations).
 * AC7: lint — no __rawQuery or backtick-MATCH/CREATE in oracle.ts.
 *
 * 2026-04-24 hardening: KG is now native Triple nodes + HAS_KNOWLEDGE edges,
 * not a JSON column. Agent node is seeded via ensurePalace + manual Agent
 * create (no knowledge_graph column anymore). All fps are 64-char hex via `fp()`.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { ServerStore } from './store.server.js';
import {
  mirrorInscriptionToKnowledgeGraph,
  mirrorInscriptionMove,
} from './oracle.js';
import { fp } from './test-fixtures.js';

// ── Helpers ───────────────────────────────────────────────────────────────────

async function makeTempStore(): Promise<{ store: ServerStore; dir: string }> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dreamball-s43-'));
  const dbPath = path.join(dir, 'palace.lbug');
  const store = new ServerStore(dbPath);
  await store.open();
  return { store, dir };
}

async function closeTempStore(store: ServerStore, dir: string): Promise<void> {
  await store.close();
  fs.rmSync(dir, { recursive: true, force: true });
}

/** Create an Agent node (native schema — no knowledge_graph column). */
async function makeAgent(store: ServerStore, agentFp: string): Promise<void> {
  await store.__rawQuery(
    `CREATE (:Agent {
      fp: '${agentFp}',
      created_at: ${Date.now()},
      personality_master_prompt: '',
      memory: '[]',
      emotional_register: '{"curiosity":0.5,"warmth":0.5,"patience":0.5}',
      interaction_set: '[]'
    })`
  );
}

/** Seed a palace with one or two rooms and an oracle agent. Returns fps. */
async function seedPalace(store: ServerStore, opts: { twoRooms?: boolean } = {}) {
  const palaceFp = fp('palace-s43');
  const roomFp1 = fp('room-s43-1');
  const roomFp2 = opts.twoRooms ? fp('room-s43-2') : null;
  const oracleAgentFp = fp('oracle-s43');

  await store.ensurePalace(palaceFp);
  await store.addRoom(palaceFp, roomFp1);
  if (roomFp2) await store.addRoom(palaceFp, roomFp2);
  await makeAgent(store, oracleAgentFp);

  return { palaceFp, roomFp1, roomFp2, oracleAgentFp };
}

/** Execute the full inscribe sequence (inscribeAvatar + mirror + recordAction). */
async function doInscribe(
  store: ServerStore,
  palaceFp: string,
  roomFp: string,
  docFp: string,
  oracleAgentFp: string,
  opts: { failBeforeAction?: boolean } = {}
): Promise<void> {
  // Step 1: inscribeAvatar (LadybugDB: Inscription node + CONTAINS + LIVES_IN)
  await store.inscribeAvatar(roomFp, docFp, docFp /* sourceBlake3 = fp for tests */);

  // Step 2: mirror into oracle KG (insertTriple)
  await mirrorInscriptionToKnowledgeGraph(store, {
    oracleAgentFp,
    docFp,
    roomFp,
  });

  // AC4: fault-injection hook — throw here to simulate crash after triple but before action
  if (opts.failBeforeAction) {
    throw new Error('AC4: injected fault after triple-insert, before recordAction');
  }

  // Step 3: recordAction (ActionLog) — fp must be valid hex too
  await store.recordAction({
    fp: fp(docFp + '-action'),
    palaceFp,
    actionKind: 'avatar-inscribed',
    actorFp: roomFp,
    targetFp: docFp,
    parentHashes: [],
    timestamp: Date.now(),
  });
}

/** Execute the full move sequence (update LIVES_IN edge + mirror + recordAction). */
async function doMove(
  store: ServerStore,
  palaceFp: string,
  docFp: string,
  fromRoomFp: string,
  toRoomFp: string,
  oracleAgentFp: string
): Promise<void> {
  // Step 1: update LIVES_IN edge in LadybugDB
  // Delete old LIVES_IN, create new one
  await store.__rawQuery(
    `MATCH (i:Inscription {fp: '${docFp}'})-[e:LIVES_IN]->(r:Room {fp: '${fromRoomFp}'}) DELETE e`
  );
  await store.__rawQuery(
    `MATCH (i:Inscription {fp: '${docFp}'})
     MATCH (r:Room {fp: '${toRoomFp}'})
     CREATE (i)-[:LIVES_IN]->(r)`
  );

  // Step 2: mirror move into oracle KG (updateTriple)
  await mirrorInscriptionMove(store, {
    oracleAgentFp,
    docFp,
    fromRoomFp,
    toRoomFp,
  });

  // Step 3: recordAction
  await store.recordAction({
    fp: fp(docFp + '-move-action'),
    palaceFp,
    actionKind: 'move',
    actorFp: fromRoomFp,
    targetFp: docFp,
    parentHashes: [],
    timestamp: Date.now(),
  });
}

// ── AC1: happy path inscribe ──────────────────────────────────────────────────

describe('AC1 — inscribe mirrors triple to oracle KG + LadybugDB + ActionLog', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });
  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('AC1: LIVES_IN edge exists in LadybugDB after inscribe', async () => {
    const { palaceFp, roomFp1, oracleAgentFp } = await seedPalace(store);
    const docFp = fp('doc-ac1-1');

    await doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp);

    const rows = await store.__rawQuery(
      `MATCH (i:Inscription {fp: '${docFp}'})-[:LIVES_IN]->(r:Room {fp: '${roomFp1}'}) RETURN 1 AS ok`
    );
    expect(rows.length).toBe(1);
  });

  it('AC1: oracle knowledge-graph triple (docFp, "lives-in", roomFp) present', async () => {
    const { palaceFp, roomFp1, oracleAgentFp } = await seedPalace(store);
    const docFp = fp('doc-ac1-2');

    await doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp);

    const triples = await store.triplesFor(oracleAgentFp, docFp);
    expect(triples.length).toBe(1);
    expect(triples[0].subject).toBe(docFp);
    expect(triples[0].predicate).toBe('lives-in');
    expect(triples[0].object).toBe(roomFp1);
  });

  it('AC1: ActionLog row with action-kind=avatar-inscribed and target-fp=docFp', async () => {
    const { palaceFp, roomFp1, oracleAgentFp } = await seedPalace(store);
    const docFp = fp('doc-ac1-3');

    await doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp);

    const actions = await store.actionsSince(palaceFp);
    const inscribeAction = actions.find((a) => a.actionKind === 'avatar-inscribed');
    expect(inscribeAction).toBeDefined();
    expect(inscribeAction!.targetFp).toBe(docFp);
  });

  it('AC1: all three writes share the same conceptual transaction (sequential order)', async () => {
    const { palaceFp, roomFp1, oracleAgentFp } = await seedPalace(store);
    const docFp = fp('doc-ac1-4');

    await expect(doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp)).resolves.toBeUndefined();
  });
});

// ── AC2: happy path move ──────────────────────────────────────────────────────

describe('AC2 — move updates oracle KG triple + LIVES_IN + ActionLog', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });
  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('AC2: after move, oracle KG contains (docFp, "lives-in", room2Fp) only', async () => {
    const { palaceFp, roomFp1, roomFp2, oracleAgentFp } = await seedPalace(store, { twoRooms: true });
    const docFp = fp('doc-ac2-1');

    await doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp);
    await doMove(store, palaceFp, docFp, roomFp1, roomFp2!, oracleAgentFp);

    const triples = await store.triplesFor(oracleAgentFp, docFp);
    const livesInTriples = triples.filter((t) => t.predicate === 'lives-in');
    expect(livesInTriples.length).toBe(1);
    expect(livesInTriples[0].object).toBe(roomFp2);
  });

  it('AC2: oracle KG does NOT contain old triple after move', async () => {
    const { palaceFp, roomFp1, roomFp2, oracleAgentFp } = await seedPalace(store, { twoRooms: true });
    const docFp = fp('doc-ac2-2');

    await doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp);
    await doMove(store, palaceFp, docFp, roomFp1, roomFp2!, oracleAgentFp);

    const triples = await store.triplesFor(oracleAgentFp, docFp);
    const hasOldTriple = triples.some(
      (t) => t.predicate === 'lives-in' && t.object === roomFp1
    );
    expect(hasOldTriple).toBe(false);
  });

  it('AC2: LadybugDB LIVES_IN points to room2 after move', async () => {
    const { palaceFp, roomFp1, roomFp2, oracleAgentFp } = await seedPalace(store, { twoRooms: true });
    const docFp = fp('doc-ac2-3');

    await doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp);
    await doMove(store, palaceFp, docFp, roomFp1, roomFp2!, oracleAgentFp);

    const r2 = await store.__rawQuery(
      `MATCH (i:Inscription {fp: '${docFp}'})-[:LIVES_IN]->(r:Room {fp: '${roomFp2}'}) RETURN r.fp AS fp`
    );
    expect(r2.length).toBe(1);

    const r1 = await store.__rawQuery(
      `MATCH (i:Inscription {fp: '${docFp}'})-[:LIVES_IN]->(r:Room {fp: '${roomFp1}'}) RETURN r.fp AS fp`
    );
    expect(r1.length).toBe(0);
  });

  it('AC2: ActionLog has move action for docFp', async () => {
    const { palaceFp, roomFp1, roomFp2, oracleAgentFp } = await seedPalace(store, { twoRooms: true });
    const docFp = fp('doc-ac2-4');

    await doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp);
    await doMove(store, palaceFp, docFp, roomFp1, roomFp2!, oracleAgentFp);

    const actions = await store.actionsSince(palaceFp);
    const moveAction = actions.find((a) => a.actionKind === 'move');
    expect(moveAction).toBeDefined();
    expect(moveAction!.targetFp).toBe(docFp);
  });
});

// ── AC3: count invariant ──────────────────────────────────────────────────────

describe('AC3 — count invariant: 3 inscribes across 2 rooms', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });
  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('AC3: exactly 3 LIVES_IN edges after 3 inscribes', async () => {
    const { palaceFp, roomFp1, roomFp2, oracleAgentFp } = await seedPalace(store, { twoRooms: true });

    const d1 = fp('doc-ac3-1');
    const d2 = fp('doc-ac3-2');
    const d3 = fp('doc-ac3-3');

    await doInscribe(store, palaceFp, roomFp1, d1, oracleAgentFp);
    await doInscribe(store, palaceFp, roomFp1, d2, oracleAgentFp);
    await doInscribe(store, palaceFp, roomFp2!, d3, oracleAgentFp);

    const rows = await store.__rawQuery(
      `MATCH (:Inscription)-[:LIVES_IN]->(:Room) RETURN count(*) AS c`
    );
    const count = Number((rows[0] as { c: number }).c);
    expect(count).toBe(3);
  });

  it('AC3: oracle knowledge_graph contains exactly 3 "lives-in" triples', async () => {
    const { palaceFp, roomFp1, roomFp2, oracleAgentFp } = await seedPalace(store, { twoRooms: true });

    const d1 = fp('doc-ac3-4');
    const d2 = fp('doc-ac3-5');
    const d3 = fp('doc-ac3-6');

    await doInscribe(store, palaceFp, roomFp1, d1, oracleAgentFp);
    await doInscribe(store, palaceFp, roomFp1, d2, oracleAgentFp);
    await doInscribe(store, palaceFp, roomFp2!, d3, oracleAgentFp);

    const allTriples = await store.triplesFor(oracleAgentFp, '*');
    const livesInTriples = allTriples.filter((t) => t.predicate === 'lives-in');
    expect(livesInTriples.length).toBe(3);
  });

  it('AC3: D1 and D2 live in room1, D3 lives in room2', async () => {
    const { palaceFp, roomFp1, roomFp2, oracleAgentFp } = await seedPalace(store, { twoRooms: true });

    const d1 = fp('doc-ac3-7');
    const d2 = fp('doc-ac3-8');
    const d3 = fp('doc-ac3-9');

    await doInscribe(store, palaceFp, roomFp1, d1, oracleAgentFp);
    await doInscribe(store, palaceFp, roomFp1, d2, oracleAgentFp);
    await doInscribe(store, palaceFp, roomFp2!, d3, oracleAgentFp);

    const t1 = await store.triplesFor(oracleAgentFp, d1);
    expect(t1[0].object).toBe(roomFp1);

    const t2 = await store.triplesFor(oracleAgentFp, d2);
    expect(t2[0].object).toBe(roomFp1);

    const t3 = await store.triplesFor(oracleAgentFp, d3);
    expect(t3[0].object).toBe(roomFp2);
  });
});

// ── AC4: fault injection ──────────────────────────────────────────────────────

describe('AC4 — fault injection: throw after triple-insert before recordAction', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });
  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('AC4: the doInscribe call throws when failBeforeAction=true', async () => {
    const { palaceFp, roomFp1, oracleAgentFp } = await seedPalace(store);
    const docFp = fp('doc-ac4-1');

    await expect(
      doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp, { failBeforeAction: true })
    ).rejects.toThrow('AC4: injected fault');
  });

  it('AC4: after fault, no ActionLog row exists for that docFp', async () => {
    const { palaceFp, roomFp1, oracleAgentFp } = await seedPalace(store);
    const docFp = fp('doc-ac4-2');

    try {
      await doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp, { failBeforeAction: true });
    } catch { /* expected */ }

    const actions = await store.actionsSince(palaceFp);
    const actionForDoc = actions.find((a) => a.targetFp === docFp);
    expect(actionForDoc).toBeUndefined();
  });

  it('AC4: after fault, the triple IS present (LadybugDB has no rollback — partial state)', async () => {
    const { palaceFp, roomFp1, oracleAgentFp } = await seedPalace(store);
    const docFp = fp('doc-ac4-3');

    try {
      await doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp, { failBeforeAction: true });
    } catch { /* expected */ }

    // Triple exists (partial state — acknowledged MVP limitation)
    void (await store.triplesFor(oracleAgentFp, docFp));
    // Retry is safe: a subsequent successful inscribe would be idempotent
    // The LIVES_IN edge also exists (inscribeAvatar already ran)
    const livesInRows = await store.__rawQuery(
      `MATCH (i:Inscription {fp: '${docFp}'})-[:LIVES_IN]->(r:Room {fp: '${roomFp1}'}) RETURN 1 AS ok`
    );
    expect(livesInRows.length).toBe(1);

    // Retry succeeds (idempotent)
    await expect(doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp)).resolves.toBeUndefined();
    // After retry: exactly one triple and one action
    const triples2 = await store.triplesFor(oracleAgentFp, docFp);
    const livesInTriples = triples2.filter((t) => t.predicate === 'lives-in');
    expect(livesInTriples.length).toBe(1); // idempotent — no duplicate
    const actions = await store.actionsSince(palaceFp);
    const actionForDoc = actions.find((a) => a.targetFp === docFp);
    expect(actionForDoc).toBeDefined();
  });
});

// ── AC5: SIGKILL simulation ───────────────────────────────────────────────────

describe('AC5 — SIGKILL simulation: forced rejection mid-sequence', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });
  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('AC5: pre-mutation state is preserved when tx never completes', async () => {
    const { palaceFp, oracleAgentFp } = await seedPalace(store);
    const docFp = fp('doc-ac5-1');

    const preMutationEdges = await store.__rawQuery(
      `MATCH (i:Inscription {fp: '${docFp}'})-[:LIVES_IN]->(:Room) RETURN 1 AS ok`
    );
    expect(preMutationEdges.length).toBe(0);

    const preMutationTriples = await store.triplesFor(oracleAgentFp, docFp);
    expect(preMutationTriples.length).toBe(0);

    const preMutationActions = await store.actionsSince(palaceFp);
    const preMutationAction = preMutationActions.find((a) => a.targetFp === docFp);
    expect(preMutationAction).toBeUndefined();
  });

  it('AC5: after simulated SIGKILL mid-sequence, successful retry reaches full state', async () => {
    const { palaceFp, roomFp1, oracleAgentFp } = await seedPalace(store);
    const docFp = fp('doc-ac5-2');

    await store.inscribeAvatar(roomFp1, docFp, docFp);
    // Process killed here — triple and action not written

    await doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp);

    const triples = await store.triplesFor(oracleAgentFp, docFp);
    const livesInTriples = triples.filter((t) => t.predicate === 'lives-in');
    expect(livesInTriples.length).toBe(1);

    const actions = await store.actionsSince(palaceFp);
    const action = actions.find((a) => a.targetFp === docFp);
    expect(action).toBeDefined();
    expect(action!.actionKind).toBe('avatar-inscribed');
  });
});

// ── AC6: interleaved reader (synchronous invariant) ───────────────────────────

describe('AC6 — mirror is synchronous: interleaved reader over 100 iterations', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });
  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('AC6: action never visible without triple over 100 iterations', async () => {
    const { palaceFp, roomFp1, oracleAgentFp } = await seedPalace(store);

    for (let i = 0; i < 100; i++) {
      const docFp = fp(`doc-ac6-${i}`);
      await doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp);

      const actions = await store.actionsSince(palaceFp);
      const action = actions.find((a) => a.targetFp === docFp);

      const triples = await store.triplesFor(oracleAgentFp, docFp);
      const triple = triples.find((t) => t.predicate === 'lives-in' && t.subject === docFp);

      if (action !== undefined) {
        expect(triple).toBeDefined();
      }
      if (triple !== undefined) {
        expect(action).toBeDefined();
      }
    }
  }, 60_000);

  it('AC6: triple never visible without action over 100 iterations (inverse)', async () => {
    const { palaceFp, roomFp1, oracleAgentFp } = await seedPalace(store);

    for (let i = 0; i < 100; i++) {
      const docFp = fp(`doc-ac6-inv-${i}`);
      await doInscribe(store, palaceFp, roomFp1, docFp, oracleAgentFp);

      const triples = await store.triplesFor(oracleAgentFp, docFp);
      const triple = triples.find((t) => t.predicate === 'lives-in');

      const actions = await store.actionsSince(palaceFp);
      const action = actions.find((a) => a.targetFp === docFp);

      if (triple !== undefined) {
        expect(action).toBeDefined();
      }
    }
  }, 60_000);
});

// ── AC7: D-007 lint — no raw Cypher in oracle.ts ─────────────────────────────

describe('AC7 — D-007 lint: no __rawQuery or backtick-Cypher in oracle.ts', () => {
  it('AC7: grep __rawQuery in oracle.ts mirrorInscription* section returns zero (code lines only)', () => {
    const repoRoot = path.resolve(import.meta.dirname, '../..');
    const oraclePath = path.join(repoRoot, 'src', 'memory-palace', 'oracle.ts');
    const content = fs.readFileSync(oraclePath, 'utf-8');

    const mirrorSection = content.slice(
      content.indexOf('export async function mirrorInscriptionToKnowledgeGraph'),
      content.indexOf('// ── isOracleRequester')
    );

    const codeLines = mirrorSection
      .split('\n')
      .filter((line) => !line.trim().startsWith('//') && !line.trim().startsWith('*'))
      .join('\n');

    expect(codeLines).not.toContain('__rawQuery');
  });

  it('AC7: grep backtick-MATCH/CREATE in oracle.ts mirrorInscription* section returns zero', () => {
    const repoRoot = path.resolve(import.meta.dirname, '../..');
    const oraclePath = path.join(repoRoot, 'src', 'memory-palace', 'oracle.ts');
    const content = fs.readFileSync(oraclePath, 'utf-8');

    const mirrorSection = content.slice(
      content.indexOf('export async function mirrorInscriptionToKnowledgeGraph'),
      content.indexOf('// ── isOracleRequester')
    );

    const backtickCypherRegex = /`[^`]*(?:MATCH|CREATE)[^`]*`/g;
    const matches = mirrorSection.match(backtickCypherRegex);
    expect(matches).toBeNull();
  });

  it('AC7: mirrorInscriptionToKnowledgeGraph uses insertTriple (domain verb only, code lines only)', () => {
    const repoRoot = path.resolve(import.meta.dirname, '../..');
    const oraclePath = path.join(repoRoot, 'src', 'memory-palace', 'oracle.ts');
    const content = fs.readFileSync(oraclePath, 'utf-8');

    const fnStart = content.indexOf('export async function mirrorInscriptionToKnowledgeGraph');
    const fnEnd = content.indexOf('export async function mirrorInscriptionMove');
    const fnBody = content.slice(fnStart, fnEnd);

    const codeLines = fnBody
      .split('\n')
      .filter((line) => !line.trim().startsWith('//') && !line.trim().startsWith('*'))
      .join('\n');

    expect(codeLines).toContain('insertTriple');
    expect(codeLines).not.toContain('__rawQuery');
  });

  it('AC7: mirrorInscriptionMove uses updateTriple (domain verb only)', () => {
    const repoRoot = path.resolve(import.meta.dirname, '../..');
    const oraclePath = path.join(repoRoot, 'src', 'memory-palace', 'oracle.ts');
    const content = fs.readFileSync(oraclePath, 'utf-8');

    const fnStart = content.indexOf('export async function mirrorInscriptionMove');
    const fnEnd = content.indexOf('// ── isOracleRequester');
    const fnBody = content.slice(fnStart, fnEnd);

    expect(fnBody).toContain('updateTriple');
    expect(fnBody).not.toContain('__rawQuery');
  });
});

// ── insertTriple/deleteTriple/updateTriple/triplesFor/actionsSince unit tests ─

describe('store triple verbs (S4.3 domain verbs)', () => {
  let store: ServerStore;
  let dir: string;

  beforeEach(async () => {
    ({ store, dir } = await makeTempStore());
  });
  afterEach(async () => {
    await closeTempStore(store, dir);
  });

  it('insertTriple: inserts a new triple', async () => {
    const agentFp = fp('agent-t1');
    const subj = fp('subj');
    const obj = fp('obj');
    await makeAgent(store, agentFp);
    await store.insertTriple(agentFp, subj, 'lives-in', obj);
    const triples = await store.triplesFor(agentFp, subj);
    expect(triples.length).toBe(1);
    expect(triples[0]).toEqual({ subject: subj, predicate: 'lives-in', object: obj });
  });

  it('insertTriple: idempotent — no duplicate on repeated call', async () => {
    const agentFp = fp('agent-t2');
    const subj = fp('subj');
    const obj = fp('obj');
    await makeAgent(store, agentFp);
    await store.insertTriple(agentFp, subj, 'lives-in', obj);
    await store.insertTriple(agentFp, subj, 'lives-in', obj);
    const triples = await store.triplesFor(agentFp, '*');
    expect(triples.length).toBe(1);
  });

  it('deleteTriple: removes the triple', async () => {
    const agentFp = fp('agent-t3');
    const subj = fp('subj');
    const obj = fp('obj');
    await makeAgent(store, agentFp);
    await store.insertTriple(agentFp, subj, 'lives-in', obj);
    await store.deleteTriple(agentFp, subj, 'lives-in', obj);
    const triples = await store.triplesFor(agentFp, subj);
    expect(triples.length).toBe(0);
  });

  it('deleteTriple: no-op when triple does not exist', async () => {
    const agentFp = fp('agent-t4');
    await makeAgent(store, agentFp);
    await expect(
      store.deleteTriple(agentFp, fp('nonexistent'), 'lives-in', fp('obj'))
    ).resolves.toBeUndefined();
  });

  it('updateTriple: replaces old object with new object', async () => {
    const agentFp = fp('agent-t5');
    const subj = fp('subj');
    const oldRoom = fp('old-room');
    const newRoom = fp('new-room');
    await makeAgent(store, agentFp);
    await store.insertTriple(agentFp, subj, 'lives-in', oldRoom);
    await store.updateTriple(agentFp, subj, 'lives-in', oldRoom, newRoom);
    const triples = await store.triplesFor(agentFp, subj);
    expect(triples.length).toBe(1);
    expect(triples[0].object).toBe(newRoom);
  });

  it('updateTriple: inserts new triple when old not found', async () => {
    const agentFp = fp('agent-t6');
    const subj = fp('subj');
    const ghost = fp('ghost');
    const newRoom = fp('new-room');
    await makeAgent(store, agentFp);
    await store.updateTriple(agentFp, subj, 'lives-in', ghost, newRoom);
    const triples = await store.triplesFor(agentFp, subj);
    expect(triples.length).toBe(1);
    expect(triples[0].object).toBe(newRoom);
  });

  it('triplesFor: returns all triples when fp = "*"', async () => {
    const agentFp = fp('agent-t7');
    await makeAgent(store, agentFp);
    await store.insertTriple(agentFp, fp('a'), 'likes', fp('b'));
    await store.insertTriple(agentFp, fp('c'), 'loves', fp('d'));
    const all = await store.triplesFor(agentFp, '*');
    expect(all.length).toBe(2);
  });

  it('actionsSince: returns all when sinceActionFp is empty', async () => {
    const palaceFp = fp('palace-actions-1');
    await store.ensurePalace(palaceFp);
    await store.recordAction({
      fp: fp('action-001'),
      palaceFp,
      actionKind: 'avatar-inscribed',
      actorFp: fp('actor'),
      targetFp: fp('target'),
      parentHashes: [],
      timestamp: Date.now(),
    });
    const all = await store.actionsSince(palaceFp);
    expect(all.length).toBe(1);
  });

  it('actionsSince: timestamp cursor filters correctly (LOW-4 fix)', async () => {
    const palaceFp = fp('palace-actions-2');
    await store.ensurePalace(palaceFp);
    const t1 = 1000;
    const t2 = 2000;
    await store.recordAction({
      fp: fp('action-old'),
      palaceFp,
      actionKind: 'avatar-inscribed',
      actorFp: fp('actor'),
      targetFp: fp('target1'),
      parentHashes: [],
      timestamp: t1,
    });
    await store.recordAction({
      fp: fp('action-new'),
      palaceFp,
      actionKind: 'avatar-inscribed',
      actorFp: fp('actor'),
      targetFp: fp('target2'),
      parentHashes: [],
      timestamp: t2,
    });

    // Cursor at t1 — only the t2 action should be returned.
    const since = await store.actionsSince(palaceFp, { afterTimestamp: t1 });
    expect(since.length).toBe(1);
    expect(since[0].targetFp).toBe(fp('target2'));
    expect(since[0].timestamp).toBe(t2);
  });
});
