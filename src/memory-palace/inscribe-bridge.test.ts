/**
 * inscribe-bridge.test.ts — Smoke-tier tests for S6.2 inscribe-bridge.ts.
 *
 * AC1 (online happy path): inscribeWithEmbedding calls embedFor → recordAction → inscribeAvatar.
 * AC4 (offline): EmbeddingServiceUnreachable → inscribeOffline emits inscription-pending-embedding.
 * AC5 (SEC11 ordering): recordAction called BEFORE inscribeAvatar; if recordAction throws,
 *      inscribeAvatar never called.
 * AC8 (content-type inference): inferContentType maps extensions correctly.
 *
 * Test tier: smoke (happy-path; edge cases deferred to S6.3 thorough tier).
 * Env: JELLY_EMBED_MOCK=hash (set by vite.config.ts server project env).
 */

import { describe, it, expect, vi } from 'vitest';
import { createHash } from 'node:crypto';
import type { StoreAPI, RecordActionParams } from './store-types.js';
import {
  inscribeWithEmbedding,
  inscribeOffline,
  inferContentType,
  EmbeddingServiceUnreachable,
} from './inscribe-bridge.js';

// ── Test helpers ──────────────────────────────────────────────────────────────

function makeFp(seed: string): string {
  return createHash('sha256').update(seed).digest('hex').padStart(64, '0').slice(0, 64);
}

/**
 * Minimal mock StoreAPI tracking action log and inscriptions for ordering assertions.
 */
function makeMockStore(opts: {
  recordActionThrow?: boolean;
} = {}): StoreAPI & {
  _actionLog: Array<{ fp: string; actionKind: string }>;
  _inscriptions: Array<{ fp: string; embedding: Float32Array | null | undefined }>;
  _callOrder: string[];
  _upsertLog: Array<{ fp: string; vec: Float32Array }>;
} {
  const _actionLog: Array<{ fp: string; actionKind: string }> = [];
  const _inscriptions: Array<{ fp: string; embedding: Float32Array | null | undefined }> = [];
  const _callOrder: string[] = [];
  const _upsertLog: Array<{ fp: string; vec: Float32Array }> = [];

  return {
    _actionLog,
    _inscriptions,
    _callOrder,
    _upsertLog,

    async recordAction(params: RecordActionParams) {
      _callOrder.push('recordAction');
      if (opts.recordActionThrow) throw new Error('recordAction: simulated failure');
      _actionLog.push({ fp: params.fp, actionKind: String(params.actionKind) });
    },

    async inscribeAvatar(
      _roomFp: string,
      avatarFp: string,
      _sourceBlake3: string,
      opts2?: { surface?: string; embedding?: Float32Array | null; archiform?: string }
    ) {
      _callOrder.push('inscribeAvatar');
      _inscriptions.push({ fp: avatarFp, embedding: opts2?.embedding ?? null });
    },

    async upsertEmbedding(fp: string, vec: Float32Array) {
      _callOrder.push('upsertEmbedding');
      _upsertLog.push({ fp, vec });
    },

    // Stub out all other StoreAPI methods (not needed for these tests).
    async open() {},
    async close() {},
    async syncfs() {},
    async ensurePalace() {},
    async addRoom() {},
    async setMythosHead() {},
    async appendMythos() {},
    async getMythosHead() { return null; },
    async headHashes() { return []; },
    async deleteEmbedding() {},
    async reembed() {},
    async kNN() { return []; },
    async getOrCreateAqueduct() { return makeFp('aq'); },
    async updateAqueductStrength() {},
    async recordTraversal() {
      return { moveActionFp: '', aqueductCreated: false, aqueductFp: '', newStrength: 0, newConductance: 0, newRevision: 0, timestamp: 0 };
    },
    async insertTriple() {},
    async deleteTriple() {},
    async updateTriple() {},
    async triplesFor() { return []; },
    async actionsSince() { return []; },
    async updateInscription() {},
    async markOrphaned() {},
    async getInscription() { return null; },
    async mythosChainTriples() { return []; },
    async inscriptionBody() { return new Uint8Array(0); },
    async inscriptionMeta() { return null; },
    async getPalace() { return null; },
    async roomsFor() { return []; },
    async roomContents() { return []; },
    async __rawQuery() { return []; },
    setWriteContext() { return () => {}; },
    registerOracleFp() {},
  } as unknown as ReturnType<typeof makeMockStore>;
}

// ── inferContentType (AC8) ────────────────────────────────────────────────────

describe('inferContentType — AC8 content-type from file extension', () => {
  it('.md → text/markdown', () => {
    expect(inferContentType('note.md')).toBe('text/markdown');
  });

  it('.txt → text/plain', () => {
    expect(inferContentType('note.txt')).toBe('text/plain');
  });

  it('.adoc → text/asciidoc', () => {
    expect(inferContentType('note.adoc')).toBe('text/asciidoc');
  });

  it('.xyz (unknown) → text/plain fallback', () => {
    // Spy on stderr to verify warning is emitted (AC8 spec)
    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const result = inferContentType('note.xyz');
    expect(result).toBe('text/plain');
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('unknown file extension'));
    stderrSpy.mockRestore();
  });

  it('no extension → text/plain fallback', () => {
    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const result = inferContentType('Makefile');
    expect(result).toBe('text/plain');
    stderrSpy.mockRestore();
  });
});

// ── inscribeWithEmbedding — AC1 (online happy path) ──────────────────────────

describe('inscribeWithEmbedding — AC1 online happy path', () => {
  it('calls embedFor, recordAction, inscribeAvatar, upsertEmbedding in SEC11 order', async () => {
    const store = makeMockStore();
    const palaceFp = makeFp('palace');
    const roomFp = makeFp('room');
    const inscriptionFp = makeFp('inscription');
    const actionFp = makeFp('action');
    const actorFp = makeFp('actor');

    await inscribeWithEmbedding({
      store,
      palaceFp,
      roomFp,
      inscriptionFp,
      actionFp,
      sourceBlake3: makeFp('source'),
      actorFp,
      parentHashes: [],
      content: 'hello palace',
      contentType: 'text/markdown',
      // JELLY_EMBED_MOCK=hash is set via vite.config.ts env — no live server needed
      embedViaUrl: 'http://localhost:9808/embed',
    });

    // Action was recorded
    expect(store._actionLog).toHaveLength(1);
    expect(store._actionLog[0].actionKind).toBe('avatar-inscribed');

    // Inscription was created
    expect(store._inscriptions).toHaveLength(1);
    expect(store._inscriptions[0].fp).toBe(inscriptionFp);

    // Embedding is present and is 256d
    const emb = store._inscriptions[0].embedding;
    expect(emb).toBeInstanceOf(Float32Array);
    expect((emb as Float32Array).length).toBe(256);

    // upsertEmbedding was called
    expect(store._upsertLog).toHaveLength(1);
    expect(store._upsertLog[0].fp).toBe(inscriptionFp);
  });

  it('SEC11: recordAction is called BEFORE inscribeAvatar', async () => {
    const store = makeMockStore();
    await inscribeWithEmbedding({
      store,
      palaceFp: makeFp('p'),
      roomFp: makeFp('r'),
      inscriptionFp: makeFp('i'),
      actionFp: makeFp('a'),
      sourceBlake3: makeFp('s'),
      actorFp: makeFp('actor'),
      parentHashes: [],
      content: 'test content',
      contentType: 'text/plain',
      embedViaUrl: 'http://localhost:9808/embed',
    });

    const raIdx = store._callOrder.indexOf('recordAction');
    const iaIdx = store._callOrder.indexOf('inscribeAvatar');
    expect(raIdx).toBeGreaterThanOrEqual(0);
    expect(iaIdx).toBeGreaterThan(raIdx);
  });
});

// ── inscribeOffline — AC4 (offline path) ─────────────────────────────────────

describe('inscribeOffline — AC4 offline path emits inscription-pending-embedding', () => {
  it('records inscription-pending-embedding action BEFORE inscribeAvatar (no embedding)', async () => {
    const store = makeMockStore();
    const palaceFp = makeFp('palace');
    const roomFp = makeFp('room');
    const inscriptionFp = makeFp('inscription');
    const actionFp = makeFp('action');
    const actorFp = makeFp('actor');

    await inscribeOffline({
      store,
      palaceFp,
      roomFp,
      inscriptionFp,
      actionFp,
      sourceBlake3: makeFp('source'),
      actorFp,
      parentHashes: [],
    });

    // Action kind is inscription-pending-embedding
    expect(store._actionLog).toHaveLength(1);
    expect(store._actionLog[0].actionKind).toBe('inscription-pending-embedding');

    // Inscription was created WITHOUT embedding (null)
    expect(store._inscriptions).toHaveLength(1);
    expect(store._inscriptions[0].embedding).toBeNull();

    // No upsertEmbedding call
    expect(store._upsertLog).toHaveLength(0);
  });

  it('SEC11: recordAction before inscribeAvatar in offline path', async () => {
    const store = makeMockStore();
    await inscribeOffline({
      store,
      palaceFp: makeFp('p'),
      roomFp: makeFp('r'),
      inscriptionFp: makeFp('i'),
      actionFp: makeFp('a'),
      sourceBlake3: makeFp('s'),
      actorFp: makeFp('actor'),
      parentHashes: [],
    });

    const raIdx = store._callOrder.indexOf('recordAction');
    const iaIdx = store._callOrder.indexOf('inscribeAvatar');
    expect(raIdx).toBeGreaterThanOrEqual(0);
    expect(iaIdx).toBeGreaterThan(raIdx);
  });
});

// ── SEC11 rollback — AC5 ──────────────────────────────────────────────────────

describe('SEC11 rollback — AC5: if recordAction throws, inscribeAvatar never called', () => {
  it('online path: recordAction throws → inscribeAvatar not called', async () => {
    const store = makeMockStore({ recordActionThrow: true });

    await expect(
      inscribeWithEmbedding({
        store,
        palaceFp: makeFp('p'),
        roomFp: makeFp('r'),
        inscriptionFp: makeFp('i'),
        actionFp: makeFp('a'),
        sourceBlake3: makeFp('s'),
        actorFp: makeFp('actor'),
        parentHashes: [],
        content: 'test',
        contentType: 'text/plain',
        embedViaUrl: 'http://localhost:9808/embed',
      })
    ).rejects.toThrow('recordAction: simulated failure');

    // inscribeAvatar must NOT have been called
    expect(store._inscriptions).toHaveLength(0);
    expect(store._callOrder.includes('inscribeAvatar')).toBe(false);
  });

  it('offline path: recordAction throws → inscribeAvatar not called', async () => {
    const store = makeMockStore({ recordActionThrow: true });

    await expect(
      inscribeOffline({
        store,
        palaceFp: makeFp('p'),
        roomFp: makeFp('r'),
        inscriptionFp: makeFp('i'),
        actionFp: makeFp('a'),
        sourceBlake3: makeFp('s'),
        actorFp: makeFp('actor'),
        parentHashes: [],
      })
    ).rejects.toThrow('recordAction: simulated failure');

    expect(store._inscriptions).toHaveLength(0);
    expect(store._callOrder.includes('inscribeAvatar')).toBe(false);
  });
});

// ── EmbeddingServiceUnreachable ───────────────────────────────────────────────

describe('EmbeddingServiceUnreachable', () => {
  it('is instanceof EmbeddingServiceUnreachable', () => {
    const err = new EmbeddingServiceUnreachable(null, 'http://localhost:9808/embed');
    expect(err).toBeInstanceOf(EmbeddingServiceUnreachable);
    expect(err.embedUrl).toBe('http://localhost:9808/embed');
    expect(err.statusCode).toBeNull();
    expect(err.message).toContain('embedding service unreachable');
  });

  it('includes HTTP status in message when statusCode provided', () => {
    const err = new EmbeddingServiceUnreachable(503, 'http://gpu.local/embed');
    expect(err.statusCode).toBe(503);
    expect(err.message).toContain('503');
  });
});
