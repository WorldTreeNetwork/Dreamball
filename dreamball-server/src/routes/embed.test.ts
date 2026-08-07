/**
 * embed.test.ts — S6.1 thorough test suite for POST /embed
 *
 * Test tier: thorough (happy paths, edge cases, error handling).
 * Tests run against the Elysia app in mock mode (DREAMBALL_EMBED_MOCK=1)
 * so no live Qwen3 model is needed in CI.
 *
 * ACs covered:
 *   AC1  — happy path: 200, correct D-012 schema, 256d vector, all finite
 *   AC2  — determinism: same input → byte-identical vectors
 *   AC3  — MRL truncation unit test: capability truncates 1024→256 (first dims)
 *   AC4  — rejects unsupported content-type: 415 + supported-set message
 *   AC5  — rejects oversize content: 413 + 1 MB limit message
 *   AC6  — no batch/stream: route module inspection
 *   AC7  — TODO-EMBEDDING markers present in route + adapter
 *   AC8  — mock determinism: blake3-seeded, not imported by index.ts
 *   AC10 — provider binds once: provider.load() spy through resolveTextEmbed
 */

// Set env before any imports so index.ts skip-listen guard fires
process.env.DREAMBALL_SERVER_NO_LISTEN = '1';
process.env.DREAMBALL_EMBED_MOCK = '1';  // use mock backend — no live model in tests

import { describe, it, expect, vi, beforeAll, afterAll } from 'vitest';
import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';
import { moduleDir } from '../paths.js';

const HERE = moduleDir(import.meta.url, import.meta.dir);

// ---------------------------------------------------------------------------
// AC8: mock NOT imported by index.ts (static grep assertion)
// ---------------------------------------------------------------------------

describe('AC8 — embed.mock not imported by index.ts', () => {
  it('grep "embed.mock" in dreamball-server/src/index.ts returns empty', () => {
    const indexSrc = readFileSync(resolve(HERE, '../index.ts'), 'utf8');
    expect(indexSrc).not.toMatch(/embed\.mock/);
  });
});

// ---------------------------------------------------------------------------
// AC6 — no batch/stream in route module (static grep assertion)
// ---------------------------------------------------------------------------

describe('AC6 — no batch or streaming (D-012 negative)', () => {
  it('route module content field is scalar string, not array', () => {
    const routeSrc = readFileSync(resolve(HERE, './embed.ts'), 'utf8');
    // request content must be t.String, not t.Array
    expect(routeSrc).toMatch(/content.*t\.String/);
    // no batch route definition
    expect(routeSrc).not.toMatch(/\/embed\/batch/);
    expect(routeSrc).not.toMatch(/\/embed\/stream/);
  });

  it('response vector is built as Array.from — the only array-type in response', () => {
    const routeSrc = readFileSync(resolve(HERE, './embed.ts'), 'utf8');
    // vector is assembled via Array.from(truncated) — sole array in response
    expect(routeSrc).toMatch(/Array\.from/);
    // response object has a "vector" key
    expect(routeSrc).toMatch(/vector:/);
    // content field in body schema is t.String (scalar), NOT t.Array
    const bodySection = routeSrc.match(/body:.*?contentType/s)?.[0] ?? '';
    expect(bodySection).not.toMatch(/t\.Array/);
  });
});

// ---------------------------------------------------------------------------
// AC7 — TODO-EMBEDDING markers present in route + adapter
// ---------------------------------------------------------------------------

describe('AC7 — TODO-EMBEDDING markers', () => {
  it('routes/embed.ts has TODO-EMBEDDING: bring-model-local-or-byo', () => {
    const src = readFileSync(resolve(HERE, './embed.ts'), 'utf8');
    expect(src).toMatch(/TODO-EMBEDDING: bring-model-local-or-byo/);
  });

  it('capabilities/text-embed/runpod.ts has TODO-EMBEDDING: bring-model-local-or-byo', () => {
    const src = readFileSync(resolve(HERE, '../capabilities/text-embed/runpod.ts'), 'utf8');
    expect(src).toMatch(/TODO-EMBEDDING: bring-model-local-or-byo/);
  });

  it('at least 2 TODO-EMBEDDING markers across route + adapter', () => {
    const routeSrc = readFileSync(resolve(HERE, './embed.ts'), 'utf8');
    const adapterSrc = readFileSync(
      resolve(HERE, '../capabilities/text-embed/runpod.ts'), 'utf8');
    const combined = routeSrc + adapterSrc;
    const matches = combined.match(/TODO-EMBEDDING: bring-model-local-or-byo/g) ?? [];
    expect(matches.length).toBeGreaterThanOrEqual(2);
  });
});

// ---------------------------------------------------------------------------
// No in-process model runtime (2026-08-07 boundary cut)
// ---------------------------------------------------------------------------

describe('no in-process embedding model in dreamball-server', () => {
  it('src/embedding/ is gone', () => {
    expect(existsSync(resolve(HERE, '../embedding'))).toBe(false);
  });

  it('dreamball-server/package.json does not depend on @huggingface/transformers', () => {
    const pkg = readFileSync(resolve(HERE, '../../package.json'), 'utf8');
    expect(pkg).not.toMatch(/@huggingface\/transformers/);
  });

  it('no source file imports @huggingface/transformers or onnxruntime', () => {
    for (const f of ['./embed.ts',
                     '../capabilities/text-embed/providers.ts',
                     '../capabilities/text-embed/resolver.ts',
                     '../capabilities/text-embed/runpod.ts',
                     '../index.ts']) {
      const src = readFileSync(resolve(HERE, f), 'utf8');
      // Import statements only — the words still appear in prose comments
      // explaining what was removed, which is the point.
      expect(src).not.toMatch(
        /(?:from|import\()\s*['"](?:@huggingface\/transformers|onnxruntime[^'"]*)['"]/);
    }
  });
});

// ---------------------------------------------------------------------------
// AC3 — MRL truncation unit: first 256 dims of 1024d output
// ---------------------------------------------------------------------------

describe('AC3 — MRL truncation (unit: text-embed capability)', () => {
  it('truncateMrl returns first 256 dims of a 1024d Float32Array', async () => {
    const { truncateMrl } = await import('../capabilities/text-embed/truncate.js');
    // build a 1024d vector with known values
    const full = new Float32Array(1024);
    for (let i = 0; i < 1024; i++) full[i] = i * 0.001;

    const truncated = truncateMrl(full, 256);
    expect(truncated).toHaveLength(256);
    // first dim should be full[0]
    expect(truncated[0]).toBeCloseTo(0.0, 5);
    // 255th dim should be full[255]
    expect(truncated[255]).toBeCloseTo(255 * 0.001, 5);
    // must NOT include dim 256+
    expect(truncated.length).toBe(256);
  });

  it('truncateMrl takes FIRST dims, not last', async () => {
    const { truncateMrl } = await import('../capabilities/text-embed/truncate.js');
    const full = new Float32Array(1024);
    full[0] = 999; // mark the first
    full[1023] = -999; // mark the last
    const truncated = truncateMrl(full, 256);
    // first element should be the marked first
    expect(truncated[0]).toBe(999);
    // last element (255) should NOT be -999 (which is at index 1023)
    expect(truncated[255]).not.toBe(-999);
  });
});

// ---------------------------------------------------------------------------
// App import (after env is set)
// ---------------------------------------------------------------------------

import { app } from '../index.js';

// ---------------------------------------------------------------------------
// AC1 — happy path
// ---------------------------------------------------------------------------

describe('AC1 — POST /embed happy path (mock mode)', () => {
  it('returns 200 with correct D-012 schema for markdown content', async () => {
    const res = await app.handle(
      new Request('http://localhost/embed', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          content: 'hello palace',
          contentType: 'text/markdown'
        })
      })
    );
    expect(res.status).toBe(200);
    const data = await res.json() as Record<string, unknown>;

    // D-012 schema fields
    expect(data).toHaveProperty('vector');
    expect(data).toHaveProperty('model');
    expect(data).toHaveProperty('dimension');
    expect(data).toHaveProperty('truncation');

    // vector: 256d, all finite
    const vector = data['vector'] as number[];
    expect(Array.isArray(vector)).toBe(true);
    expect(vector.length).toBe(256);
    for (const v of vector) {
      expect(Number.isFinite(v)).toBe(true);
    }

    // model + dimension + truncation literals
    expect(data['model']).toBe('qwen3-embedding-0.6b');
    expect(data['dimension']).toBe(256);
    expect(data['truncation']).toBe('mrl-256');
  });

  it('accepts text/plain content type', async () => {
    const res = await app.handle(
      new Request('http://localhost/embed', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          content: 'plain text content',
          contentType: 'text/plain'
        })
      })
    );
    expect(res.status).toBe(200);
    const data = await res.json() as Record<string, unknown>;
    expect((data['vector'] as number[]).length).toBe(256);
  });

  it('accepts text/asciidoc content type', async () => {
    const res = await app.handle(
      new Request('http://localhost/embed', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          content: '= AsciiDoc Title\nsome content',
          contentType: 'text/asciidoc'
        })
      })
    );
    expect(res.status).toBe(200);
    const data = await res.json() as Record<string, unknown>;
    expect((data['vector'] as number[]).length).toBe(256);
  });
});

// ---------------------------------------------------------------------------
// AC2 — determinism
// ---------------------------------------------------------------------------

describe('AC2 — determinism: same input → byte-identical vectors', () => {
  it('two identical requests return the same 256 floats', async () => {
    const body = JSON.stringify({
      content: 'memory palace test content',
      contentType: 'text/markdown'
    });

    const res1 = await app.handle(
      new Request('http://localhost/embed', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body
      })
    );
    const res2 = await app.handle(
      new Request('http://localhost/embed', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body
      })
    );

    expect(res1.status).toBe(200);
    expect(res2.status).toBe(200);

    const d1 = await res1.json() as { vector: number[]; model: string; dimension: number };
    const d2 = await res2.json() as { vector: number[]; model: string; dimension: number };

    // All 256 floats must be identical
    expect(d1.vector).toHaveLength(256);
    expect(d2.vector).toHaveLength(256);
    for (let i = 0; i < 256; i++) {
      expect(d1.vector[i]).toBe(d2.vector[i]);
    }

    // model and dimension stable
    expect(d1.model).toBe(d2.model);
    expect(d1.dimension).toBe(d2.dimension);
  });
});

// ---------------------------------------------------------------------------
// AC4 — 415 on unsupported content-type
// ---------------------------------------------------------------------------

describe('AC4 — 415 on unsupported content-type', () => {
  it('returns 415 for application/pdf', async () => {
    const res = await app.handle(
      new Request('http://localhost/embed', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          content: 'some content',
          contentType: 'application/pdf'
        })
      })
    );
    expect(res.status).toBe(415);
    const data = await res.json() as Record<string, unknown>;
    // must name supported set
    const bodyStr = JSON.stringify(data);
    expect(bodyStr).toMatch(/text\/markdown|text\/plain|text\/asciidoc/);
  });

  it('returns 415 for image/png', async () => {
    const res = await app.handle(
      new Request('http://localhost/embed', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          content: 'some content',
          contentType: 'image/png'
        })
      })
    );
    expect(res.status).toBe(415);
  });
});

// ---------------------------------------------------------------------------
// AC5 — 413 on oversize content
// ---------------------------------------------------------------------------

describe('AC5 — 413 on oversize content (>1 MB)', () => {
  it('returns 413 when content exceeds 1 MB', async () => {
    // 1 MB + 1 byte of content
    const oversize = 'a'.repeat(1_048_577);
    const res = await app.handle(
      new Request('http://localhost/embed', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          content: oversize,
          contentType: 'text/markdown'
        })
      })
    );
    expect(res.status).toBe(413);
    const data = await res.json() as Record<string, unknown>;
    const bodyStr = JSON.stringify(data);
    // must mention 1 MB limit
    expect(bodyStr).toMatch(/1\s*MB|1048576|1_048_576/i);
  });

  it('accepts content exactly at 1 MB boundary', async () => {
    const exactly1MB = 'a'.repeat(1_048_576);
    const res = await app.handle(
      new Request('http://localhost/embed', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          content: exactly1MB,
          contentType: 'text/plain'
        })
      })
    );
    // should not be 413
    expect(res.status).not.toBe(413);
  });
});

// ---------------------------------------------------------------------------
// AC8 — mock determinism
// ---------------------------------------------------------------------------

describe('AC8 — mock backend determinism', () => {
  it('mockEmbed returns 256d vector derived deterministically from content', async () => {
    const { mockEmbed } = await import('./embed.mock.js');
    const v1 = await mockEmbed({ content: 'hello palace', contentType: 'text/markdown' });
    const v2 = await mockEmbed({ content: 'hello palace', contentType: 'text/markdown' });
    expect(v1).toHaveLength(256);
    expect(v2).toHaveLength(256);
    for (let i = 0; i < 256; i++) {
      expect(v1[i]).toBe(v2[i]);
    }
  });

  it('mockEmbed returns different vectors for different content', async () => {
    const { mockEmbed } = await import('./embed.mock.js');
    const v1 = await mockEmbed({ content: 'alpha content', contentType: 'text/markdown' });
    const v2 = await mockEmbed({ content: 'beta content', contentType: 'text/markdown' });
    expect(v1).not.toEqual(v2);
  });

  it('mock module has TODO-EMBEDDING marker', async () => {
    const src = readFileSync(resolve(HERE, './embed.mock.ts'), 'utf8');
    expect(src).toMatch(/TODO-EMBEDDING/);
  });
});

// ---------------------------------------------------------------------------
// AC10 — model loads once at boot
// ---------------------------------------------------------------------------

describe('AC10 — provider binds once (spy on provider.load)', () => {
  it('the bound provider load()s at most once across multiple embed requests', async () => {
    // The AC10 invariant survived the removal of the in-process ONNX loader:
    // it was never about ONNX, it was about "the expensive setup runs once".
    // That guard now lives in the resolver's binding cache, so spy there.
    const { TEXT_EMBED_PROVIDERS } = await import(
      '../capabilities/text-embed/providers.js');
    const { resetTextEmbedBinding } = await import(
      '../capabilities/text-embed/resolver.js');

    resetTextEmbedBinding();
    const provider = TEXT_EMBED_PROVIDERS.find((p) => p.available());
    expect(provider).toBeDefined();
    const spy = vi.spyOn(provider!, 'load');

    // Make 3 consecutive requests (mock mode — no actual model load)
    for (let i = 0; i < 3; i++) {
      await app.handle(
        new Request('http://localhost/embed', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            content: `request number ${i}`,
            contentType: 'text/markdown'
          })
        })
      );
    }

    // Exactly once: the first request binds and loads; requests 2 and 3 reuse
    // the cached binding. This is now a real assertion rather than the old
    // "<= 1" (which mock mode satisfied vacuously with 0 calls).
    expect(spy.mock.calls.length).toBe(1);
    spy.mockRestore();
  });
});
