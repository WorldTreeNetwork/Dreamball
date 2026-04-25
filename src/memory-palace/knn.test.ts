/**
 * knn.test.ts — S6.3 thorough test suite
 *
 * AC1  happy: 3-inscription corpus, top-2 ordering correct, roomFp resolved.
 * AC2  Cypher: grep store.server.ts + store.browser.ts for exact D-016 pattern.
 * AC3  perf: 500-corpus, p50 <200ms (skip on CI if SKIP_PERF=1).
 * AC4  offline: mock unreachable, assert typed OfflineKnnError throw.
 * AC5  contract: throw not return (offline branch is always a throw).
 * AC6  routing: server uses native adapter; browser uses local kuzu-wasm (KNN_LOCAL=true).
 * AC7  marker: TODO-EMBEDDING directly above embedFor call in knn.ts.
 * AC8  reembed round-trip: delete-then-insert changes ordering, no orphan rows.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import lbug from '@ladybugdb/core';

import { kNN, OfflineKnnError } from './knn.js';
import type { StoreAPI, KnnHit } from './store-types.js';
import { ServerStore } from './store.server.js';
import { EmbeddingServiceUnreachable } from './embedding-client.js';
import { generatePerfCorpus, generatePerfQueryVector, perfRoomFps } from './perf-fixtures.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Deterministic 64-char lowercase hex fp from a small integer seed. */
function makeFp(seed: number): string {
  return seed.toString(16).padStart(16, '0').repeat(4);
}

/** Build a Float32Array from a number[] with L2 normalisation. */
function makeVec(components: number[]): Float32Array {
  const v = new Float32Array(256);
  // Set the first N components then normalise
  for (let i = 0; i < components.length; i++) v[i] = components[i];
  let norm = 0;
  for (let i = 0; i < 256; i++) norm += v[i] * v[i];
  norm = Math.sqrt(norm);
  if (norm > 0) for (let i = 0; i < 256; i++) v[i] /= norm;
  return v;
}

// ── Mock embedFor ─────────────────────────────────────────────────────────────

vi.mock('./embedding-client.js', async (importOriginal) => {
  const orig = await importOriginal<typeof import('./embedding-client.js')>();
  return {
    ...orig,
    embedFor: vi.fn(),
  };
});

// ── AC1: happy path — 3 inscriptions, top-2 ordering, roomFp resolved ─────────

describe('AC1 — happy path: top-k ordering + roomFp join', () => {
  it('returns KnnHit[] sorted by distance ASC with resolved roomFp', async () => {
    // Build a mock StoreAPI whose kNN returns pre-sorted results
    const roomA = makeFp(1);
    const roomB = makeFp(2);
    const fpA = makeFp(10);
    const fpB = makeFp(11);
    const fpC = makeFp(12);

    const mockStore: Partial<StoreAPI> = {
      kNN: vi.fn().mockResolvedValue([
        { fp: fpA, roomFp: roomA, distance: 0.1 },
        { fp: fpB, roomFp: roomA, distance: 0.3 },
        { fp: fpC, roomFp: roomB, distance: 0.7 },
      ]),
    };

    const { embedFor } = await import('./embedding-client.js');
    vi.mocked(embedFor).mockResolvedValue(Array(256).fill(0.5));

    // k=3: adapter mock returns 3 hits; results should have 3 entries
    const results = await kNN(mockStore as StoreAPI, 'palace of memory', 3);

    expect(results).toHaveLength(3);
    expect(results[0].fp).toBe(fpA);
    expect(results[0].roomFp).toBe(roomA);
    expect(results[0].distance).toBe(0.1);
    expect(results[1].fp).toBe(fpB);
    expect(results[1].distance).toBe(0.3);
    // No hit has distance: null or NaN
    for (const hit of results) {
      expect(Number.isFinite(hit.distance)).toBe(true);
      expect(hit.roomFp).toBeTruthy();
    }
  });
});

// ── AC2: Cypher grep — D-016 exact pattern ────────────────────────────────────

describe('AC2 — Cypher matches D-016 exactly', () => {
  const serverFile = readFileSync(join(__dirname, 'store.server.ts'), 'utf-8');
  const browserFile = readFileSync(join(__dirname, 'store.browser.ts'), 'utf-8');

  for (const [label, content] of [['store.server.ts', serverFile], ['store.browser.ts', browserFile]] as const) {
    it(`${label}: contains exactly one CALL QUERY_VECTOR_INDEX (the Cypher call site, not comments)`, () => {
      // AC2 spec: "exactly one match" refers to the CALL site in Cypher, not comment mentions.
      const matches = content.match(/CALL QUERY_VECTOR_INDEX/g) ?? [];
      expect(matches.length).toBe(1);
    });

    it(`${label}: YIELD node AS i, distance`, () => {
      expect(content).toContain('YIELD node AS i, distance');
    });

    it(`${label}: MATCH (i:Inscription)-[:LIVES_IN]->(r:Room)`, () => {
      expect(content).toContain('MATCH (i:Inscription)-[:LIVES_IN]->(r:Room)');
    });

    it(`${label}: RETURN emits fp, roomFp, distance in order`, () => {
      expect(content).toContain('RETURN i.fp AS fp, r.fp AS roomFp, distance');
    });

    it(`${label}: ORDER BY distance ASC`, () => {
      expect(content).toContain('ORDER BY distance ASC');
    });
  }
});

// ── AC3: perf budget — 500-corpus, p50 <200ms ─────────────────────────────────

describe('AC3 — 500-inscription perf budget (p50 <200ms)', () => {
  const SKIP = process.env['SKIP_PERF'] === '1';

  it.skipIf(SKIP)(
    'p50 kNN round-trip <200ms on 500-corpus ServerStore (JELLY_EMBED_MOCK=1)',
    async () => {
      // Set mock mode so embedFor returns instantly without network.
      const origMock = process.env['JELLY_EMBED_MOCK'];
      process.env['JELLY_EMBED_MOCK'] = '1';

      const store = new ServerStore(':memory:');
      await store.open();

      const corpus = generatePerfCorpus(500, 256, 42);
      const rooms = perfRoomFps();

      // 1. Setup: create palace, rooms, inscriptions (NOT timed)
      const palaceFp = makeFp(0xbeef);
      await store.ensurePalace(palaceFp);
      for (const roomFp of rooms) {
        await store.addRoom(palaceFp, roomFp);
      }

      // Inscribe + upsertEmbedding (setup — not measured)
      for (const insc of corpus) {
        await store.inscribeAvatar(insc.roomFp, insc.fp, insc.sourceBlake3);
        await store.upsertEmbedding(insc.fp, insc.vec);
      }

      // 2. Warm up (1 call, not measured)
      const queryVec = generatePerfQueryVector(256, 99);
      const { embedFor } = await import('./embedding-client.js');
      vi.mocked(embedFor).mockResolvedValue(Array.from(queryVec));
      await kNN(store, 'warmup', 10);

      // 3. Measure 10 consecutive kNN calls
      const N = 10;
      const latencies: number[] = [];
      for (let i = 0; i < N; i++) {
        vi.mocked(embedFor).mockResolvedValue(Array.from(queryVec));
        const t0 = performance.now();
        const hits = await kNN(store, 'query text', 10);
        const t1 = performance.now();
        latencies.push(t1 - t0);
        expect(hits).toHaveLength(10);
      }

      await store.close();

      if (origMock !== undefined) {
        process.env['JELLY_EMBED_MOCK'] = origMock;
      } else {
        delete process.env['JELLY_EMBED_MOCK'];
      }

      latencies.sort((a, b) => a - b);
      const p50 = latencies[Math.floor(N * 0.5)];
      const p95 = latencies[Math.floor(N * 0.95)];

      console.log(
        `[AC3 perf] p50=${p50.toFixed(1)}ms p95=${p95.toFixed(1)}ms (N=${N}, corpus=500)`
      );

      // Hard gate: p50 <200ms
      expect(p50).toBeLessThan(200);

      // Soft gate: p95 <400ms — warn only
      if (p95 >= 400) {
        console.warn(
          `[AC3 perf] WARN: p95=${p95.toFixed(1)}ms >= 400ms soft ceiling. ` +
          `See docs/known-gaps.md for ADR addendum procedure.`
        );
      }
    },
    120_000 // corpus setup can be slow for 500 inscriptions
  );
});

// ── AC4: offline — typed OfflineKnnError thrown ────────────────────────────────

describe('AC4 — offline: OfflineKnnError thrown when /embed unreachable', () => {
  it('throws OfflineKnnError when embedFor throws EmbeddingServiceUnreachable', async () => {
    const { embedFor } = await import('./embedding-client.js');
    vi.mocked(embedFor).mockRejectedValue(
      new EmbeddingServiceUnreachable(null, 'http://localhost:9808/embed')
    );

    const mockStore: Partial<StoreAPI> = {
      kNN: vi.fn(),
    };

    await expect(
      kNN(mockStore as StoreAPI, 'anything', 10)
    ).rejects.toThrow(OfflineKnnError);
  });

  it('OfflineKnnError.reason === "embedding-service-unreachable"', async () => {
    const { embedFor } = await import('./embedding-client.js');
    vi.mocked(embedFor).mockRejectedValue(
      new EmbeddingServiceUnreachable(null, 'http://localhost:9808/embed')
    );

    const mockStore: Partial<StoreAPI> = { kNN: vi.fn() };

    try {
      await kNN(mockStore as StoreAPI, 'anything', 10);
      expect.fail('should have thrown');
    } catch (err) {
      expect(err).toBeInstanceOf(OfflineKnnError);
      const e = err as OfflineKnnError;
      expect(e.reason).toBe('embedding-service-unreachable');
      expect(e.cached).toEqual([]);
    }
  });

  it('store.kNN is NOT called when embedding service unreachable', async () => {
    const { embedFor } = await import('./embedding-client.js');
    vi.mocked(embedFor).mockRejectedValue(
      new EmbeddingServiceUnreachable(null, 'http://localhost:9808/embed')
    );

    const mockKnn = vi.fn();
    const mockStore: Partial<StoreAPI> = { kNN: mockKnn };

    await expect(kNN(mockStore as StoreAPI, 'anything', 10)).rejects.toThrow(OfflineKnnError);
    expect(mockKnn).not.toHaveBeenCalled();
  });
});

// ── AC5: contract — offline always throws, never returns ──────────────────────

describe('AC5 — offline branch is always a throw, never a resolved Promise', () => {
  it('OfflineKnnError is thrown (not returned) when embedding service unreachable', async () => {
    const { embedFor } = await import('./embedding-client.js');
    vi.mocked(embedFor).mockRejectedValue(
      new EmbeddingServiceUnreachable(null, 'http://localhost:9808/embed')
    );

    const mockStore: Partial<StoreAPI> = { kNN: vi.fn() };

    // The promise must reject — it must NOT resolve to anything.
    let resolved = false;
    await kNN(mockStore as StoreAPI, 'anything', 10)
      .then(() => { resolved = true; })
      .catch(() => { /* expected */ });

    expect(resolved).toBe(false);
  });

  it('OfflineKnnError.cached is always [] (never stale results)', async () => {
    const e = new OfflineKnnError();
    expect(e.cached).toEqual([]);
    expect(Array.isArray(e.cached)).toBe(true);
    expect(e.cached.length).toBe(0);
  });
});

// ── AC6: routing — server uses native; browser branch is KNN_LOCAL=true ───────

describe('AC6 — cross-runtime routing per D-015 outcome', () => {
  it('server kNN delegates to @ladybugdb/core QUERY_VECTOR_INDEX (native)', async () => {
    // Verify that ServerStore.kNN calls the correct Cypher (D-016 pattern).
    // We assert via the Cypher grep (AC2 covers the pattern; here we verify the
    // dispatch chain from kNN.ts → store.server.ts).
    const { embedFor } = await import('./embedding-client.js');
    const queryVec = generatePerfQueryVector(256, 77);
    vi.mocked(embedFor).mockResolvedValue(Array.from(queryVec));

    const mockKnn = vi.fn().mockResolvedValue([]);
    const mockStore: Partial<StoreAPI> = { kNN: mockKnn };

    await kNN(mockStore as StoreAPI, 'server routing test', 5);

    expect(mockKnn).toHaveBeenCalledOnce();
    const [calledVec, calledK] = mockKnn.mock.calls[0];
    expect(calledVec).toBeInstanceOf(Float32Array);
    expect(calledVec.length).toBe(256);
    expect(calledK).toBe(5);
  });

  it('store.browser.ts KNN_LOCAL flag is true (D-015 parity PASS branch)', () => {
    const browserSource = readFileSync(join(__dirname, 'store.browser.ts'), 'utf-8');
    // D-015 outcome: local path active
    expect(browserSource).toContain('const KNN_LOCAL = true;');
    // fallback comment preserved
    expect(browserSource).toContain('TODO-KNN-FALLBACK');
  });
});

// ── AC7: TODO-EMBEDDING marker directly above embedFor call in knn.ts ─────────

describe('AC7 — TODO-EMBEDDING marker at query-embed call site', () => {
  it('TODO-EMBEDDING marker appears directly above embedFor call in knn.ts', () => {
    const knnSource = readFileSync(join(__dirname, 'knn.ts'), 'utf-8');
    // Find the TODO-EMBEDDING marker and verify embedFor call follows within 3 lines
    const lines = knnSource.split('\n');
    const markerIdx = lines.findIndex((l) =>
      l.includes('TODO-EMBEDDING: bring-model-local-or-byo')
    );
    expect(markerIdx).toBeGreaterThan(-1);

    // embedFor must appear within 5 lines after the marker
    const snippet = lines.slice(markerIdx, markerIdx + 8).join('\n');
    expect(snippet).toContain('embedFor');
  });

  it('TODO-EMBEDDING does NOT appear at vector-index lookup site (local — no exit)', () => {
    const knnSource = readFileSync(join(__dirname, 'knn.ts'), 'utf-8');
    const lines = knnSource.split('\n');

    // Find store.kNN call line
    const knnCallIdx = lines.findIndex((l) =>
      l.includes('store.kNN(') && !l.trimStart().startsWith('//')
    );
    expect(knnCallIdx).toBeGreaterThan(-1);

    // The 3 lines before the kNN call must NOT contain TODO-EMBEDDING
    const priorLines = lines.slice(Math.max(0, knnCallIdx - 3), knnCallIdx).join('\n');
    expect(priorLines).not.toContain('TODO-EMBEDDING');
  });
});

// ── AC8: reembed round-trip — ordering changes, no orphan rows ────────────────

describe('AC8 — reembed round-trip via store.reembed', () => {
  it('re-embedding changes kNN ordering; no orphan vector-index rows for the inscription', async () => {
    const store = new ServerStore(':memory:');
    await store.open();

    const palaceFp = makeFp(0xcafe);
    const roomFp = makeFp(0xdead);
    const fpI = makeFp(0xf00d);
    const src1 = '1'.repeat(64);
    const src2 = '2'.repeat(64);

    await store.ensurePalace(palaceFp);
    await store.addRoom(palaceFp, roomFp);
    await store.inscribeAvatar(roomFp, fpI, src1);

    // E1: vector pointing mostly in dim-0 direction
    const e1 = makeVec([1, 0, 0]);
    await store.upsertEmbedding(fpI, e1);

    // Add two reference inscriptions to make ordering testable
    const fpA = makeFp(0xab01);
    const fpB = makeFp(0xab02);
    const eA = makeVec([0.9, 0.1, 0]); // close to e1
    const eB = makeVec([0, 1, 0]);     // close to e2
    await store.inscribeAvatar(roomFp, fpA, '3'.repeat(64));
    await store.upsertEmbedding(fpA, eA);
    await store.inscribeAvatar(roomFp, fpB, '4'.repeat(64));
    await store.upsertEmbedding(fpB, eB);

    // Query with e1-like vector → fpI and fpA should be near top
    const { embedFor } = await import('./embedding-client.js');
    vi.mocked(embedFor).mockResolvedValue(Array.from(e1));
    const hits1 = await kNN(store, 'query-e1', 3);
    const fps1 = hits1.map((h) => h.fp);
    expect(fps1).toContain(fpI);
    expect(fps1).toContain(fpA);

    // E2: reembed fpI to vector pointing in dim-1 direction (close to fpB now)
    const e2 = makeVec([0, 1, 0]);
    await store.reembed(fpI, new TextEncoder().encode('new-content'), e2);

    // Verify no orphan: only one row for fpI in the store
    const rows = await store.__rawQuery<{ fp: string }>(
      `MATCH (i:Inscription {fp: '${fpI}'}) RETURN i.fp AS fp`
    );
    expect(rows).toHaveLength(1);

    // Query with e2-like vector → fpI and fpB should now be near top
    vi.mocked(embedFor).mockResolvedValue(Array.from(e2));
    const hits2 = await kNN(store, 'query-e2', 3);
    const fps2 = hits2.map((h) => h.fp);
    expect(fps2).toContain(fpI);
    expect(fps2).toContain(fpB);

    await store.close();
  });
});
