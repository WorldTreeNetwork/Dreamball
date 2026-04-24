/**
 * embedding-client.ts — Seam for computing inscription embeddings (S4.4 / Epic 6).
 *
 * Exports:
 *   computeEmbedding(bytes: Uint8Array): Promise<number[]>
 *   EmbeddingServiceUnreachable — thrown when /embed returns 5xx
 *
 * Epic 6 contract: plug in Qwen3-Embedding-0.6B by pointing
 *   JELLY_EMBED_BASE at a server that implements:
 *     POST /embed  body: raw bytes  response: { embedding: number[] }
 *   The seam does NOT need to change — Epic 6 only implements the server side.
 *
 * Test-only mock mode: JELLY_EMBED_MOCK=hash returns a deterministic
 * pseudo-random float array derived from the input bytes (SHA-256 based).
 * This is NOT suitable for production use — it is only for unit tests.
 * TODO-EMBEDDING: bring-model-local-or-byo (Epic 6 replaces mock with Qwen3)
 *
 * Decisions: D-012 (single POST, no batch), D-007 (no DB access here).
 * FR21: computeEmbedding is called only when source bytes changed (AC2 guard
 *       is in file-watcher.ts, not here).
 */

// ── EmbeddingServiceUnreachable ───────────────────────────────────────────────

/**
 * Thrown when the /embed endpoint responds with a 5xx status (AC4).
 * file-watcher.ts catches this to surface "embedding service unreachable".
 */
export class EmbeddingServiceUnreachable extends Error {
  public readonly statusCode: number;

  constructor(statusCode: number, url: string) {
    super(`embedding service unreachable: POST ${url} returned ${statusCode}`);
    this.name = 'EmbeddingServiceUnreachable';
    this.statusCode = statusCode;
  }
}

// ── computeEmbedding ──────────────────────────────────────────────────────────

const EMBEDDING_DIM = 256;

/**
 * Compute an embedding vector for the given byte payload.
 *
 * In production: HTTP POST to ${JELLY_EMBED_BASE}/embed.
 * In test mock mode (JELLY_EMBED_MOCK=hash): returns a deterministic
 * pseudo-random float array derived from a hash of the bytes.
 *
 * TODO-EMBEDDING: bring-model-local-or-byo
 *   Epic 6 implements the real Qwen3-Embedding-0.6B endpoint. This
 *   seam requires no change on the caller side — only the server /embed
 *   route needs to be implemented.
 *
 * @param bytes  Raw source bytes for the inscription
 * @returns      256-dimensional float array (MRL-truncated per D-002)
 * @throws EmbeddingServiceUnreachable when /embed responds with 5xx
 */
export async function computeEmbedding(bytes: Uint8Array): Promise<number[]> {
  // Test-only mock mode: deterministic hash → float array
  // TODO-EMBEDDING: bring-model-local-or-byo
  if (typeof process !== 'undefined' && process.env.JELLY_EMBED_MOCK === 'hash') {
    return _hashToFloats(bytes);
  }

  const base = (typeof process !== 'undefined' && process.env.JELLY_EMBED_BASE)
    ? process.env.JELLY_EMBED_BASE
    : 'http://localhost:9808';

  const url = `${base}/embed`;

  // TODO-EMBEDDING: bring-model-local-or-byo
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/octet-stream' },
    body: bytes.buffer as ArrayBuffer,
  });

  if (response.status >= 500) {
    throw new EmbeddingServiceUnreachable(response.status, url);
  }

  if (!response.ok) {
    throw new Error(`computeEmbedding: unexpected HTTP ${response.status} from ${url}`);
  }

  const json = (await response.json()) as { embedding: number[] };
  if (!Array.isArray(json.embedding)) {
    throw new Error(`computeEmbedding: response missing "embedding" array from ${url}`);
  }

  return json.embedding;
}

// ── _hashToFloats (test-only mock) ────────────────────────────────────────────

/**
 * Deterministic pseudo-random float array from SHA-256 hash of input bytes.
 * ONLY used when JELLY_EMBED_MOCK=hash (test mode).
 * NOT a real embedding — purely for test assertions about delete-then-insert
 * behaviour (AC1 AC2 AC5 AC10).
 */
export async function _hashToFloats(bytes: Uint8Array): Promise<number[]> {
  const { createHash } = await import('node:crypto');
  // Expand the SHA-256 hash by iterating with different seeds to fill 256 dims
  const result: number[] = [];
  let seed = 0;
  while (result.length < EMBEDDING_DIM) {
    const h = createHash('sha256').update(bytes).update(Buffer.from([seed])).digest();
    for (let i = 0; i < h.length && result.length < EMBEDDING_DIM; i++) {
      // Map byte 0-255 to float in range [-1, 1]
      result.push((h[i] / 127.5) - 1.0);
    }
    seed++;
  }
  return result;
}
