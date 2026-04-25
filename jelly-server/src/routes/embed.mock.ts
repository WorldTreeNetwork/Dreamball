/**
 * embed.mock.ts — Deterministic mock backend for POST /embed (S6.1 AC8).
 *
 * HARNESS-ONLY: This module is imported by Vitest tests and Storybook stories.
 * It MUST NOT be imported by jelly-server/src/index.ts (production never reaches it).
 *
 * The mock derives a deterministic 256d float vector from blake3(content),
 * seeded with a byte counter. This is not a real embedding — it exists solely
 * to give tests and stories a stable, reproducible vector without a live model.
 *
 * Usage:
 *   import { mockEmbed } from 'jelly-server/src/routes/embed.mock.ts';
 *   const vector = await mockEmbed({ content: '...', contentType: 'text/markdown' });
 *
 * TODO-EMBEDDING: bring-model-local-or-byo
 *   Replace this mock with a call to the real /embed endpoint when Qwen3 weights
 *   are available locally. The JELLY_EMBED_MOCK=1 env var signals to embed.ts to
 *   use this path instead of onnxruntime-node. See S6.1 AC8.
 *
 * Decisions: D-012 (wire shape), D-002 (256d MRL target).
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface MockEmbedInput {
  content: string;
  contentType: string;
}

// ---------------------------------------------------------------------------
// mockEmbed
// ---------------------------------------------------------------------------

/**
 * Compute a deterministic 256d float vector from blake3(content).
 *
 * Algorithm:
 *   1. Encode content as UTF-8 bytes.
 *   2. Iteratively hash bytes || [seed_byte] (blake3 or SHA-256 fallback).
 *   3. Map each output byte to float in [-1, 1]: (byte / 127.5) - 1.0
 *   4. Fill 256 floats, increment seed each hash block.
 *
 * The contentType is NOT included in the hash — content identity is the seed.
 * (Real Qwen3 also doesn't alter embeddings per content-type; type is a routing hint.)
 *
 * @returns  256-element number[] (not Float32Array, to match D-012 JSON response)
 */
export async function mockEmbed(input: MockEmbedInput): Promise<number[]> {
  const bytes = new TextEncoder().encode(input.content);
  const result: number[] = [];
  let seed = 0;

  while (result.length < 256) {
    const block = await _hashBlock(bytes, seed);
    for (let i = 0; i < block.length && result.length < 256; i++) {
      result.push((block[i] / 127.5) - 1.0);
    }
    seed++;
  }

  return result;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/** Hash bytes || [seed] using Bun.hash.blake3 or node:crypto SHA-256 fallback. */
async function _hashBlock(bytes: Uint8Array, seed: number): Promise<Uint8Array> {
  const seedByte = new Uint8Array([seed & 0xff]);

  // Bun native blake3 (preferred: matches cypher-utils.ts Blake3 convention)
  const globalBun = globalThis as unknown as {
    Bun?: { hash?: { blake3?: (data: Uint8Array, opts?: { asBytes?: boolean }) => Uint8Array | string } }
  };
  if (globalBun.Bun?.hash?.blake3) {
    const combined = new Uint8Array(bytes.length + 1);
    combined.set(bytes);
    combined.set(seedByte, bytes.length);
    const h = globalBun.Bun.hash.blake3(combined, { asBytes: true });
    return h instanceof Uint8Array ? h : new TextEncoder().encode(String(h));
  }

  // Node/Vitest fallback: SHA-256 (same as embedding-client.ts _hashToFloats)
  const { createHash } = await import('node:crypto');
  const h = createHash('sha256')
    .update(bytes)
    .update(seedByte)
    .digest();
  return new Uint8Array(h.buffer, h.byteOffset, h.byteLength);
}
