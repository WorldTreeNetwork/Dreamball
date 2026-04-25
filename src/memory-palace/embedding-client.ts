/**
 * embedding-client.ts — HTTP client for the /embed endpoint (S4.4 / S6.2 / Epic 6).
 *
 * Exports:
 *   embedFor(content, contentType, embedViaUrl): Promise<number[]>
 *     — D-012 wire shape: POST { content, contentType } → { vector, model, dimension, truncation }
 *   computeEmbedding(bytes: Uint8Array): Promise<number[]>
 *     — Legacy S4.4 surface: converts bytes → text, delegates to embedFor.
 *   EmbeddingServiceUnreachable — thrown when service is unreachable or returns 5xx.
 *
 * S6.2 contract: embedFor is the SOLE HTTP call site for embedding.
 *   file-watcher.ts and inscribe-bridge.ts both import from here; neither
 *   re-implements the fetch. This is the single sanctioned network exit (NFR11).
 *
 * Test-only mock mode: JELLY_EMBED_MOCK=hash returns a deterministic
 * pseudo-random float array derived from the input bytes (SHA-256 based).
 * This is NOT suitable for production use — it is only for unit tests.
 * TODO-EMBEDDING: bring-model-local-or-byo
 *
 * Decisions: D-012 (single POST, no batch), D-007 (no DB access here).
 * FR21: computeEmbedding is called only when source bytes changed (AC2 guard
 *       is in file-watcher.ts, not here).
 */

// ── EmbeddingServiceUnreachable ───────────────────────────────────────────────

/**
 * Thrown when the /embed endpoint is unreachable (network error) or returns 5xx.
 * file-watcher.ts catches this to surface "embedding service unreachable".
 * inscribe-bridge.ts catches this to emit inscription-pending-embedding action (S6.2 AC4).
 */
export class EmbeddingServiceUnreachable extends Error {
  public readonly statusCode: number | null;
  public readonly embedUrl: string;

  constructor(statusOrNull: number | null, url: string, cause?: unknown) {
    const msg = statusOrNull !== null
      ? `embedding service unreachable at ${url} (HTTP ${statusOrNull})`
      : `embedding service unreachable at ${url}`;
    super(msg, cause ? { cause } : undefined);
    this.name = 'EmbeddingServiceUnreachable';
    this.statusCode = statusOrNull;
    this.embedUrl = url;
  }
}

// ── D-012 response shape ──────────────────────────────────────────────────────

interface EmbedResponse {
  vector: number[];
  model: string;
  dimension: number;
  truncation: string;
}

// ── embedFor ──────────────────────────────────────────────────────────────────

const EMBEDDING_DIM = 256;

/**
 * Compute an embedding vector for the given text content using D-012 wire shape.
 *
 * This is the SOLE HTTP call site for embedding (NFR11 sanctioned exit).
 * inscribe-bridge.ts and file-watcher.ts both delegate here; neither re-implements fetch.
 *
 * In production: HTTP POST { content, contentType } to embedViaUrl.
 * In test mock mode (JELLY_EMBED_MOCK=hash): returns deterministic hash-derived floats.
 *
 * TODO-EMBEDDING: bring-model-local-or-byo
 *   This client calls the jelly-server /embed endpoint (S6.1). Replace with
 *   a local WASM/ONNX call once weights are bundled locally.
 *
 * @param content      Text content to embed
 * @param contentType  MIME type (text/markdown, text/plain, text/asciidoc)
 * @param embedViaUrl  Full URL of the /embed endpoint (default: http://localhost:9808/embed)
 * @returns            256-dimensional float array (MRL-truncated per D-002)
 * @throws EmbeddingServiceUnreachable when unreachable or returns 5xx/415
 */
export async function embedFor(
  content: string,
  contentType: string,
  embedViaUrl = 'http://localhost:9808/embed'
): Promise<number[]> {
  // Test-only mock mode: deterministic hash → float array.
  // JELLY_EMBED_MOCK='1' (jelly-server convention, vite.config.ts) or
  // JELLY_EMBED_MOCK='hash' (legacy embedding-client convention) both activate mock.
  // TODO-EMBEDDING: bring-model-local-or-byo
  const mockEnv = typeof process !== 'undefined' ? process.env.JELLY_EMBED_MOCK : undefined;
  if (mockEnv === '1' || mockEnv === 'hash') {
    const bytes = new TextEncoder().encode(content);
    return _hashToFloats(bytes);
  }

  // TODO-EMBEDDING: bring-model-local-or-byo
  //   HTTP call site: POST D-012 wire shape to embedViaUrl.
  //   Single sanctioned network exit for the memory-palace (NFR11).
  let response: Response;
  try {
    response = await fetch(embedViaUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content, contentType }),
    });
  } catch (err) {
    // Network error (ECONNREFUSED, ETIMEDOUT, DNS failure, etc.)
    throw new EmbeddingServiceUnreachable(null, embedViaUrl, err);
  }

  if (response.status >= 500 || response.status === 415) {
    throw new EmbeddingServiceUnreachable(response.status, embedViaUrl);
  }

  if (!response.ok) {
    throw new Error(`embedFor: unexpected HTTP ${response.status} from ${embedViaUrl}`);
  }

  const json = (await response.json()) as EmbedResponse;
  if (!Array.isArray(json.vector)) {
    throw new Error(`embedFor: response missing "vector" array from ${embedViaUrl}`);
  }

  return json.vector;
}

// ── computeEmbedding (legacy S4.4 surface) ────────────────────────────────────

/**
 * Legacy S4.4 surface: compute embedding for raw bytes.
 * Converts bytes to UTF-8 text and delegates to embedFor.
 *
 * @deprecated Prefer embedFor() directly. This surface exists for file-watcher.ts
 *             backwards compatibility. It uses JELLY_EMBED_BASE env for the URL.
 *
 * @param bytes  Raw source bytes for the inscription
 * @returns      256-dimensional float array (MRL-truncated per D-002)
 * @throws EmbeddingServiceUnreachable when /embed responds with 5xx or is unreachable
 */
export async function computeEmbedding(bytes: Uint8Array): Promise<number[]> {
  const base = (typeof process !== 'undefined' && process.env.JELLY_EMBED_BASE)
    ? process.env.JELLY_EMBED_BASE
    : 'http://localhost:9808';
  const url = `${base}/embed`;
  const content = new TextDecoder().decode(bytes);
  return embedFor(content, 'text/plain', url);
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
