/**
 * qwen3.ts — Qwen3-Embedding-0.6B adapter for jelly-server (S6.1).
 *
 * Public surface:
 *   loadQwen3Model(): Promise<void>  — called ONCE at server boot; fail-fast if absent
 *   embed(content: string): Promise<Float32Array>  — returns 1024d raw output
 *   truncateMrl(vec: Float32Array, dim: number): Float32Array  — MRL prefix truncation
 *
 * MRL semantics: Qwen3-Embedding-0.6B is trained with Matryoshka Representation
 * Learning. The first N dimensions of the 1024d output form a semantically valid
 * N-dimensional embedding. We always take the FIRST 256 dims (not last, not
 * normalized). See D-002 and Epic 6 AC3.
 *
 * Backend selection (priority order, decided at boot):
 *   1. JELLY_EMBED_MOCK=1                              → deterministic mock
 *   2. RUNPOD_SERVERLESS_ENDPOINT_ID + RUNPOD_API_KEY  → remote Runpod (Ollama qwen3-embedding:0.6b)
 *   3. JELLY_EMBED_MODEL_PATH (or ./models default)    → local ONNX
 *   4. None of the above at boot                       → fail-fast
 *
 * TODO-EMBEDDING: bring-model-local-or-byo
 *   Three exits today: mock (CI), remote Runpod (BYO GPU), local ONNX (BYO weights).
 *   See docs/decisions/2026-04-24-qwen3-embedding-loader.md for the full ADR.
 *
 * Decisions: D-002 (Qwen3-Embedding-0.6B, 256d MRL), D-012 (single POST /embed).
 * NFR11 (sanctioned network exit), SEC6 (no implicit exfiltration).
 */

import { readRunpodConfig, embedViaRunpod, type RunpodConfig } from './runpod';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Minimal interface for the @huggingface/transformers FeatureExtractionPipeline */
interface FeatureExtractionPipeline {
  (text: string, options?: { pooling?: string; normalize?: boolean }): Promise<{
    data: Float32Array;
    dims: number[];
  }>;
}

// ---------------------------------------------------------------------------
// Singleton state
// ---------------------------------------------------------------------------

/** The singleton pipeline instance — loaded once at boot, reused forever. */
let _pipeline: FeatureExtractionPipeline | null = null;

/** Runpod config (set at boot when env vars are present, otherwise null). */
let _runpod: RunpodConfig | null = null;

/** Set to true once loadQwen3Model() has succeeded. */
let _loaded = false;

// ---------------------------------------------------------------------------
// loadQwen3Model — called once at server boot
// ---------------------------------------------------------------------------

/**
 * Load the Qwen3-Embedding-0.6B model from the pinned local path.
 *
 * Fail-fast contract: if the model directory does not exist at
 * JELLY_EMBED_MODEL_PATH, this function throws before the server
 * starts accepting requests.
 *
 * TODO-EMBEDDING: bring-model-local-or-byo
 *   Default path: ./models/Qwen3-Embedding-0.6B-ONNX
 *   Override: JELLY_EMBED_MODEL_PATH=<absolute-path>
 *   Download script: scripts/download-embed-model.ts
 */
export async function loadQwen3Model(): Promise<void> {
  if (_loaded) return;  // load-once guard

  // Mock mode: skip model load entirely (test seam, JELLY_EMBED_MOCK=1)
  if (process.env.JELLY_EMBED_MOCK === '1') {
    _loaded = true;
    return;
  }

  // Runpod mode: remote serverless GPU, no local weights needed.
  // We don't health-check at boot — first embed() call will surface auth/network errors.
  _runpod = readRunpodConfig();
  if (_runpod) {
    _loaded = true;
    return;
  }

  const modelPath = process.env.JELLY_EMBED_MODEL_PATH
    ?? './models/Qwen3-Embedding-0.6B-ONNX';

  // Fail-fast: check local path exists before attempting load
  const { existsSync } = await import('fs');
  if (!existsSync(modelPath)) {
    throw new Error(
      `embedding model not found at ${modelPath}\n` +
      `Set JELLY_EMBED_MODEL_PATH or run: bun run scripts/download-embed-model.ts`
    );
  }

  // TODO-EMBEDDING: bring-model-local-or-byo
  // Load ONNX model via @huggingface/transformers (onnxruntime-node backend).
  // The pipeline call downloads nothing — it reads from the local ONNX directory.
  const { pipeline, env } = await import('@huggingface/transformers');

  // Force local-only: disable remote model fetching
  env.allowRemoteModels = false;
  env.localModelPath = modelPath;

  _pipeline = (await pipeline('feature-extraction', modelPath, {
    dtype: 'fp32',
  })) as unknown as FeatureExtractionPipeline;

  _loaded = true;
}

// ---------------------------------------------------------------------------
// embed — produce raw 1024d vector from content string
// ---------------------------------------------------------------------------

/**
 * Compute a 1024d embedding for the given content string.
 *
 * This is the raw Qwen3-Embedding-0.6B output BEFORE MRL truncation.
 * Callers (routes/embed.ts) apply truncateMrl() before returning to clients.
 *
 * In mock mode (JELLY_EMBED_MOCK=1): returns a deterministic pseudo-random
 * 1024d Float32Array seeded from the content string's bytes.
 *
 * @throws Error if loadQwen3Model() was never called (server bug)
 */
export async function embed(content: string): Promise<Float32Array> {
  // Mock mode: deterministic hash-based embedding, no model needed
  if (process.env.JELLY_EMBED_MOCK === '1') {
    return _mockEmbed1024(content);
  }

  // Runpod path: remote GPU, Ollama qwen3-embedding:0.6b. Native dim 1024.
  if (_runpod) {
    const vec = await embedViaRunpod(content, _runpod);
    assertMrlCapacity(vec.length);
    return vec;
  }

  if (!_loaded || !_pipeline) {
    throw new Error('qwen3: model not loaded — call loadQwen3Model() at server boot');
  }

  // Run inference: pooling=mean, normalize=false (MRL prefix semantics require
  // raw unnormalized output so the truncated subspace is semantically valid)
  const output = await _pipeline(content, { pooling: 'mean', normalize: false });

  // output.data is a Float32Array of length 1024 for Qwen3-Embedding-0.6B
  assertMrlCapacity(output.data.length);

  return output.data instanceof Float32Array
    ? output.data
    : new Float32Array(output.data);
}

function assertMrlCapacity(len: number): void {
  if (len < 256) {
    throw new Error(`qwen3: unexpected output dimension ${len}, expected >= 256`);
  }
}

// ---------------------------------------------------------------------------
// truncateMrl — MRL prefix truncation
// ---------------------------------------------------------------------------

/**
 * Take the first `dim` dimensions of a full-length embedding vector.
 *
 * Qwen3-Embedding-0.6B is Matryoshka-trained: the first N dims of the 1024d
 * output form a semantically valid N-dimensional embedding. We always take the
 * FIRST 256 dims — not the last, not a random projection, not normalized.
 *
 * This is the sole truncation path: every embedding that leaves jelly-server
 * must pass through here. See AC3.
 *
 * @param vec  Full-length embedding (typically 1024d)
 * @param dim  Target dimension (256 for MVP)
 * @returns    New Float32Array of length `dim`
 */
export function truncateMrl(vec: Float32Array, dim: number): Float32Array {
  if (vec.length < dim) {
    throw new Error(`truncateMrl: vector length ${vec.length} < target dim ${dim}`);
  }
  // slice(0, dim) extracts the first `dim` elements — MRL prefix property
  return vec.slice(0, dim);
}

// ---------------------------------------------------------------------------
// _mockEmbed1024 — test-only deterministic 1024d vector
// ---------------------------------------------------------------------------

/**
 * Deterministic pseudo-random 1024d Float32Array seeded from content.
 * ONLY used when JELLY_EMBED_MOCK=1. NOT a real embedding.
 *
 * Uses Bun.hash.blake3 when available (Bun runtime), falls back to
 * node:crypto SHA-256 for Vitest worker compatibility.
 */
async function _mockEmbed1024(content: string): Promise<Float32Array> {
  const bytes = new TextEncoder().encode(content);
  const result = new Float32Array(1024);
  let offset = 0;
  let seed = 0;

  while (offset < 1024) {
    const block = await _hashBlock(bytes, seed);
    for (let i = 0; i < block.length && offset < 1024; i++) {
      result[offset++] = (block[i] / 127.5) - 1.0;
    }
    seed++;
  }
  return result;
}

/** Hash a block using Blake3 (Bun) or SHA-256 fallback. */
async function _hashBlock(bytes: Uint8Array, seed: number): Promise<Uint8Array> {
  const seedByte = new Uint8Array([seed & 0xff]);

  // Bun native blake3
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

  // Node/Vitest fallback: SHA-256
  const { createHash } = await import('node:crypto');
  const h = createHash('sha256')
    .update(bytes)
    .update(seedByte)
    .digest();
  return new Uint8Array(h.buffer, h.byteOffset, h.byteLength);
}
