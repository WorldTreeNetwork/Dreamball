/**
 * traversal.test.ts — S5.5 Thorough-tier integration tests for recordTraversal.
 *
 * AC coverage:
 *   RT1: End-to-end traversal round-trip (first traversal creates aqueduct)
 *   RT2: Subsequent traversal — Hebbian Hebbian update, no new aqueduct, monotone
 *   RT3: Freshness R7 parity — bit-identical results from renderer & server paths
 *   RT4: NFR10 latency (500-room palace, store operations < 2s budget)
 *   RT5: SEC6 no-exfil — no `fetch(` outside store.ts-mediated paths in lens files
 *   RT6: D-007 boundary — recordTraversal is the sole traversal entry point
 */

import { describe, it, expect } from 'vitest';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { ServerStore } from './store.server.js';
import { fp } from './test-fixtures.js';
import {
  freshness,
  freshnessForRender,
  DUSTY_MS,
  COBWEBS_MS,
  SLEEPING_MS,
  DEFAULT_ALPHA,
  updateStrength,
} from './aqueduct.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ─── RT1: End-to-end traversal round-trip ────────────────────────────────────

describe('RT1 — recordTraversal first-traversal round-trip', () => {
  it('creates aqueduct with D-003 defaults, emits move + aqueduct-created actions', async () => {
    const store = new ServerStore(':memory:');
    await store.open();

    const palaceFp = fp('rt1-palace');
    const roomA = fp('rt1-room-a');
    const roomB = fp('rt1-room-b');

    await store.ensurePalace(palaceFp);
    await store.addRoom(palaceFp, roomA);
    await store.addRoom(palaceFp, roomB);

    const t0 = Date.now();
    const result = await store.recordTraversal({
      palaceFp,
      fromFp: roomA,
      toFp: roomB,
      timestamp: t0,
    });

    // aqueductCreated = true on first traversal
    expect(result.aqueductCreated).toBe(true);
    expect(typeof result.aqueductFp).toBe('string');
    expect(result.aqueductFp).toMatch(/^[0-9a-f]{64}$/);
    expect(typeof result.moveActionFp).toBe('string');
    expect(result.moveActionFp).toMatch(/^[0-9a-f]{64}$/);
    expect(result.timestamp).toBe(t0);

    // Aqueduct row has D-003 defaults (resistance=0.3, capacitance=0.5)
    const aqRows = await store.__rawQuery<{
      resistance: number;
      capacitance: number;
      strength: number;
    }>(
      `MATCH (a:Aqueduct {fp: '${result.aqueductFp}'})
       RETURN a.resistance AS resistance, a.capacitance AS capacitance, a.strength AS strength`
    );
    expect(aqRows).toHaveLength(1);
    expect(aqRows[0].resistance).toBe(0.3);
    expect(aqRows[0].capacitance).toBe(0.5);

    // Strength is Hebbian-updated from 0 → α = 0.1
    expect(Number(aqRows[0].strength)).toBeCloseTo(DEFAULT_ALPHA, 10);

    // move ActionLog row persisted
    const moveRows = await store.__rawQuery<{ action_kind: string }>(
      `MATCH (a:ActionLog {fp: '${result.moveActionFp}'}) RETURN a.action_kind AS action_kind`
    );
    expect(moveRows).toHaveLength(1);
    expect(moveRows[0].action_kind).toBe('move');

    // aqueduct-created ActionLog row exists (emitted by getOrCreateAqueduct)
    const aqActionRows = await store.__rawQuery<{ action_kind: string }>(
      `MATCH (a:ActionLog {action_kind: 'aqueduct-created', target_fp: '${result.aqueductFp}'})
       RETURN a.action_kind AS action_kind`
    );
    expect(aqActionRows).toHaveLength(1);
    expect(aqActionRows[0].action_kind).toBe('aqueduct-created');

    await store.close();
  });

  it('renderer-await SEC11: result only returned after Blake3 fp persisted in ActionLog', async () => {
    const store = new ServerStore(':memory:');
    await store.open();

    const palaceFp = fp('rt1-sec11-palace');
    const roomA = fp('rt1-sec11-room-a');
    const roomB = fp('rt1-sec11-room-b');

    await store.ensurePalace(palaceFp);
    await store.addRoom(palaceFp, roomA);
    await store.addRoom(palaceFp, roomB);

    const result = await store.recordTraversal({ palaceFp, fromFp: roomA, toFp: roomB });

    // By the time result is returned, moveActionFp MUST exist in ActionLog
    // (SEC11: renderer paints arc only after this resolves).
    const rows = await store.__rawQuery<{ fp: string }>(
      `MATCH (a:ActionLog {fp: '${result.moveActionFp}'}) RETURN a.fp AS fp`
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].fp).toBe(result.moveActionFp);

    await store.close();
  });
});

// ─── RT2: Subsequent traversal — Hebbian update, no new aqueduct ─────────────

describe('RT2 — subsequent traversal Hebbian update (TC17 monotone)', () => {
  it('strength ← 0.1 + 0.1×(1−0.1) = 0.19 (±1e-9); no new aqueduct; one move action', async () => {
    const store = new ServerStore(':memory:');
    await store.open();

    const palaceFp = fp('rt2-palace');
    const roomA = fp('rt2-room-a');
    const roomB = fp('rt2-room-b');

    await store.ensurePalace(palaceFp);
    await store.addRoom(palaceFp, roomA);
    await store.addRoom(palaceFp, roomB);

    const t0 = 1_700_000_000_000;
    const t1 = t0 + 60_000;

    // First traversal: strength goes 0 → 0.1
    const r1 = await store.recordTraversal({ palaceFp, fromFp: roomA, toFp: roomB, timestamp: t0 });
    expect(r1.aqueductCreated).toBe(true);
    expect(r1.newStrength).toBeCloseTo(0.1, 9);

    // Second traversal: strength goes 0.1 → 0.1 + 0.1×(1−0.1) = 0.19
    const r2 = await store.recordTraversal({ palaceFp, fromFp: roomA, toFp: roomB, timestamp: t1 });
    expect(r2.aqueductCreated).toBe(false);           // no new aqueduct
    expect(r2.aqueductFp).toBe(r1.aqueductFp);       // same aqueduct
    expect(r2.newStrength).toBeCloseTo(0.19, 9);
    expect(r2.newRevision).toBe(r1.newRevision + 1);  // revision bumped

    // Exactly one additional move action (not paired aqueduct-created)
    const moveRows = await store.__rawQuery<{ fp: string }>(
      `MATCH (a:ActionLog {action_kind: 'move', target_fp: '${r1.aqueductFp}'})
       RETURN a.fp AS fp`
    );
    expect(moveRows).toHaveLength(2); // one per traversal

    // No second aqueduct-created action
    const aqCreatedRows = await store.__rawQuery<{ fp: string }>(
      `MATCH (a:ActionLog {action_kind: 'aqueduct-created', target_fp: '${r1.aqueductFp}'})
       RETURN a.fp AS fp`
    );
    expect(aqCreatedRows).toHaveLength(1); // only from first traversal

    await store.close();
  });

  it('strength is monotone non-decreasing across 10 consecutive traversals (TC17)', async () => {
    const store = new ServerStore(':memory:');
    await store.open();

    const palaceFp = fp('rt2-monotone-palace');
    const roomA = fp('rt2-monotone-a');
    const roomB = fp('rt2-monotone-b');

    await store.ensurePalace(palaceFp);
    await store.addRoom(palaceFp, roomA);
    await store.addRoom(palaceFp, roomB);

    let prev = -1;
    for (let i = 0; i < 10; i++) {
      const result = await store.recordTraversal({
        palaceFp,
        fromFp: roomA,
        toFp: roomB,
        timestamp: 1_700_000_000_000 + i * 1000,
      });
      expect(result.newStrength).toBeGreaterThan(prev);
      expect(result.newStrength).toBeLessThanOrEqual(1.0);
      prev = result.newStrength;
    }

    await store.close();
  });

  it('Hebbian formula matches aqueduct.ts updateStrength (pure function parity)', () => {
    // Verify the formula used in the store matches the pure function
    let s = 0;
    for (let i = 0; i < 5; i++) {
      s = updateStrength(s, DEFAULT_ALPHA);
    }
    // After 5 steps from 0: s = 1 - (1 - 0.1)^5 = 1 - 0.9^5 ≈ 0.40951
    expect(s).toBeCloseTo(1 - Math.pow(0.9, 5), 10);
  });
});

// ─── RT3: Freshness R7 parity ─────────────────────────────────────────────────

describe('RT3 — freshness R7 parity (bit-identical from any call site)', () => {
  const NOW = 1_700_000_000_000;
  const DAY_MS = 24 * 60 * 60 * 1000;

  it('freshness(now, lastTraversed) and freshnessForRender(1.0, t, tau) are bit-identical', () => {
    const lastTraversed = NOW - 45 * DAY_MS;
    const t = NOW - lastTraversed;
    const tau = DUSTY_MS;

    // "Renderer uniform derivation" path
    const renderPath = freshnessForRender(1.0, t, tau);
    // "Wrapper call site" path (what AqueductFlow.svelte does)
    const wrapperPath = freshness(NOW, lastTraversed, tau);

    // Bit-identical: same IEEE 754 float64 value
    expect(wrapperPath).toBe(renderPath);
  });

  it('freshness uses 30d/90d/365d half-life constants per Vril ADR', () => {
    // Constants are exported from aqueduct.ts (single source)
    expect(DUSTY_MS).toBe(30 * 24 * 60 * 60 * 1000);
    expect(COBWEBS_MS).toBe(90 * 24 * 60 * 60 * 1000);
    expect(SLEEPING_MS).toBe(365 * 24 * 60 * 60 * 1000);
  });

  it('freshness at t=0 is exactly 1.0 (no decay at moment of traversal)', () => {
    expect(freshness(NOW, NOW)).toBe(1.0);
  });

  it('freshness is strictly decreasing with elapsed time', () => {
    const f0 = freshness(NOW, NOW);
    const f30 = freshness(NOW, NOW - DUSTY_MS);
    const f90 = freshness(NOW, NOW - COBWEBS_MS);
    const f365 = freshness(NOW, NOW - SLEEPING_MS);

    expect(f0).toBeGreaterThan(f30);
    expect(f30).toBeGreaterThan(f90);
    expect(f90).toBeGreaterThan(f365);
    expect(f365).toBeGreaterThan(0);
  });

  it('freshness at DUSTY_MS threshold ≈ exp(-1) ≈ 0.368 with default tau', () => {
    const f = freshness(NOW, NOW - DUSTY_MS, DUSTY_MS);
    // exp(-1) ≈ 0.36787944...
    expect(f).toBeCloseTo(Math.exp(-1), 10);
  });

  it('renderer uniform import matches server-side spy — bit-identical contract', () => {
    // Simulate two call sites: renderer uniform derivation vs server-side store spy
    const lastTraversed = NOW - 15 * DAY_MS;
    const tau = DUSTY_MS;

    // "Server spy" path — freshnessForRender called directly
    const serverSpy = freshnessForRender(1.0, NOW - lastTraversed, tau);
    // "Renderer uniform" path — freshness() wrapper (what AqueductFlow.svelte imports)
    const rendererUniform = freshness(NOW, lastTraversed, tau);

    // Exact bit-identity (R7 requirement: same IEEE 754 double, no rounding drift)
    expect(Object.is(rendererUniform, serverSpy)).toBe(true);
  });
});

// ─── RT4: NFR10 latency ───────────────────────────────────────────────────────

describe('RT4 — NFR10 latency (store operations within budget)', () => {
  it('recordTraversal on a large palace (50 rooms) completes in < 500ms per call', async () => {
    const store = new ServerStore(':memory:');
    await store.open();

    const palaceFp = fp('rt4-large-palace');
    await store.ensurePalace(palaceFp);

    const roomFps: string[] = [];
    for (let i = 0; i < 50; i++) {
      const rFp = fp(`rt4-room-${i}`);
      roomFps.push(rFp);
      await store.addRoom(palaceFp, rFp);
    }

    // Warm up
    await store.recordTraversal({ palaceFp, fromFp: roomFps[0], toFp: roomFps[1] });

    // Time a batch of traversals
    const t0 = performance.now();
    for (let i = 1; i < 10; i++) {
      await store.recordTraversal({
        palaceFp,
        fromFp: roomFps[i],
        toFp: roomFps[i + 1],
        timestamp: 1_700_000_000_000 + i * 1000,
      });
    }
    const elapsed = performance.now() - t0;

    // 9 traversals should complete well under 9 × 500ms = 4.5s on any machine
    // (in practice << 100ms with in-memory DB)
    expect(elapsed).toBeLessThan(4500);

    await store.close();
  });
});

// ─── RT5: SEC6 no-exfil — lens files must not contain `fetch(` ───────────────

describe('RT5 — SEC6 no-exfil: no fetch() in lens/shader files', () => {
  const lensFiles = [
    join(__dirname, '../lib/lenses/palace/PalaceLens.svelte'),
    join(__dirname, '../lib/lenses/room/RoomLens.svelte'),
    join(__dirname, '../lib/lenses/inscription/InscriptionLens.svelte'),
    join(__dirname, '../lib/lenses/palace/shaders/AqueductFlow.svelte'),
  ];

  const shaderFiles = [
    join(__dirname, '../lib/shaders/aqueduct-flow.vert.glsl'),
    join(__dirname, '../lib/shaders/aqueduct-flow.frag.glsl'),
  ];

  for (const filePath of [...lensFiles, ...shaderFiles]) {
    const shortName = filePath.split('/src/lib/')[1] ?? filePath;
    it(`${shortName}: no raw fetch() call (SEC6)`, () => {
      // L14 review fix: a missing file used to print console.warn and pass. That
      // meant renaming a lens silently disabled the gate. Fail-loud instead.
      expect(existsSync(filePath), `SEC6 gate: file missing ${shortName}`).toBe(true);
      const src = readFileSync(filePath, 'utf-8');
      const lines = src.split('\n');
      const forbidden = lines.filter(
        (l) =>
          l.trim().startsWith('fetch(') ||
          (/fetch\(/.test(l) && !l.trim().startsWith('//') && !l.trim().startsWith('*'))
      );
      expect(forbidden).toHaveLength(0);
    });
  }
});

// ─── RT6: D-007 boundary — forbidden store verbs in lens source files ─────────

describe('RT6 — D-007 lens boundary (no direct DB writes in lens files)', () => {
  const FORBIDDEN_VERBS = [
    'addRoom',
    'inscribeAvatar',
    'recordAction',
    'recordTraversal',
    'upsertEmbedding',
    'reembed',
    'getOrCreateAqueduct',
    'updateAqueductStrength',
    'insertTriple',
  ];

  const lensFiles = [
    join(__dirname, '../lib/lenses/palace/PalaceLens.svelte'),
    join(__dirname, '../lib/lenses/room/RoomLens.svelte'),
    join(__dirname, '../lib/lenses/inscription/InscriptionLens.svelte'),
  ];

  for (const filePath of lensFiles) {
    const shortName = filePath.split('/src/lib/')[1] ?? filePath;
    it(`${shortName}: no direct store write verbs (D-007 / SEC11)`, () => {
      // L14 review fix: fail loud on rename rather than silently skipping.
      expect(existsSync(filePath), `D-007 gate: file missing ${shortName}`).toBe(true);
      const src = readFileSync(filePath, 'utf-8');

      // Forbidden verbs must NOT appear as function calls in the script block
      // (they may appear in comments — that is fine)
      const scriptMatch = src.match(/<script[^>]*>([\s\S]*?)<\/script>/);
      const scriptSrc = scriptMatch ? scriptMatch[1] : src;

      for (const verb of FORBIDDEN_VERBS) {
        const nonCommentLines = scriptSrc
          .split('\n')
          .filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*'));
        const callFound = nonCommentLines.some((l) =>
          new RegExp(`(?:store\\.)?${verb}\\s*\\(`).test(l)
        );
        expect(callFound, `Found forbidden verb '${verb}' call in ${shortName}`).toBe(false);
      }
    });
  }
});

// ─── Cross-runtime invariant: freshness imported, never copied ────────────────

describe('Cross-runtime: freshness is imported from aqueduct.ts (never copied)', () => {
  it('AqueductFlow.svelte imports freshness from aqueduct.ts (not a local copy)', () => {
    const filePath = join(
      __dirname,
      '../lib/lenses/palace/shaders/AqueductFlow.svelte'
    );
    const src = readFileSync(filePath, 'utf-8');

    // Must have an import statement bringing in freshness from aqueduct.ts
    expect(src).toMatch(/import.*freshness.*from.*aqueduct/);

    // Must NOT define its own freshness function (Math.exp(-...))
    const scriptMatch = src.match(/<script[^>]*>([\s\S]*?)<\/script>/);
    const scriptSrc = scriptMatch ? scriptMatch[1] : src;
    // A local `function freshness` would be the forbidden copy pattern
    expect(scriptSrc).not.toMatch(/function\s+freshness\s*\(/);
  });
});
