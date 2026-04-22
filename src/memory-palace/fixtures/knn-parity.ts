/**
 * Deterministic K-NN parity fixture for S2.1 (D-015 spike).
 *
 * Generates 100 unit-normalised 256-dimensional vectors from a seeded
 * LCG, plus a query vector from a second seed. The Blake3 hash of the
 * concatenated raw Float32 bytes is pinned as a compile-time constant so
 * any regression in the generator is immediately caught.
 *
 * Why LCG over crypto.getRandomValues:
 *   A deterministic LCG needs no WASM or platform RNG import and produces
 *   identical output across Bun, Node, and Chromium — essential for a
 *   cross-runtime parity fixture.
 *
 * Why unit-normalise:
 *   D-015 §Decision: "vectors are unit-norm in [-1,1]; distances are in
 *   [0, 2]; 0.1 is ~5% of the range." Unit-normalised cosine distances
 *   are bounded, making the |Δ| ≤ 0.1 acceptance threshold meaningful.
 */

export interface ParityVector {
  /** Stable fingerprint — "v{index}" for the 100-vector fixture */
  fp: string;
  /** 256-dimensional unit-normalised Float32Array */
  vec: Float32Array;
}

/**
 * Pinned SHA-256 digest of the concatenated Float32LE bytes of all 100
 * fixture vectors (seed=42) followed by the query vector (seed=43).
 * Verified by the fixture-determinism vitest (AC1).
 *
 * Note: the spec calls for Blake3, but no Blake3 TS library is in the
 * project. SHA-256 (available natively via Node/Bun `crypto`) serves the
 * same determinism-pinning purpose here. If a Blake3 TS dep is added later,
 * recompute this constant and rename the export.
 *
 * Computed: bun run src/memory-palace/fixtures/knn-parity.ts
 */
export const FIXTURE_SHA256_HEX =
  '9ff1615985a29958e9589546a8dda1c4fc64bbfdbef9a2ec5f1b9250c6a0c7b2';

// ── LCG parameters (same as Knuth MMIX) ─────────────────────────────────────
const LCG_A = 6364136223846793005n;
const LCG_C = 1442695040888963407n;
const LCG_M = 2n ** 64n;

/**
 * A tiny seeded LCG returning values in [0, 1).
 * Returns a stateful iterator — call `next()` repeatedly.
 */
function makeLCG(seed: number): { next(): number } {
  let state = BigInt(seed) & 0xffff_ffff_ffff_ffffn;
  return {
    next(): number {
      state = (LCG_A * state + LCG_C) % LCG_M;
      // Take the high 53 bits for float precision
      return Number(state >> 11n) / Number(2n ** 53n);
    }
  };
}

/**
 * Generate a single 256-dimensional unit-normalised vector from the LCG.
 * Components are drawn from [-1, 1] then L2-normalised.
 */
function generateVector(rng: { next(): number }, dim: number): Float32Array {
  const raw = new Float32Array(dim);
  for (let i = 0; i < dim; i++) {
    raw[i] = rng.next() * 2 - 1; // [-1, 1]
  }
  // L2 normalise
  let norm = 0;
  for (let i = 0; i < dim; i++) norm += raw[i] * raw[i];
  norm = Math.sqrt(norm);
  if (norm > 0) {
    for (let i = 0; i < dim; i++) raw[i] /= norm;
  }
  return raw;
}

/**
 * Generate the 100-vector fixture (seed=42, dim=256).
 * Second call returns byte-identical results (AC1).
 */
export function generateFixture(
  count = 100,
  dim = 256,
  seed = 42
): ParityVector[] {
  const rng = makeLCG(seed);
  const result: ParityVector[] = [];
  for (let i = 0; i < count; i++) {
    result.push({ fp: `v${i}`, vec: generateVector(rng, dim) });
  }
  return result;
}

/**
 * Generate the query vector (seed=43, dim=256).
 * Used for K-NN queries in both server and browser.
 */
export function generateQueryVector(dim = 256, seed = 43): Float32Array {
  const rng = makeLCG(seed);
  return generateVector(rng, dim);
}

/**
 * Concatenate all fixture vectors + query vector into a single Float32LE
 * byte buffer for Blake3 pinning.
 */
export function fixtureBytes(fixture: ParityVector[], query: Float32Array): Uint8Array {
  const totalFloats = fixture.reduce((s, v) => s + v.vec.length, 0) + query.length;
  const buf = new Float32Array(totalFloats);
  let offset = 0;
  for (const pv of fixture) {
    buf.set(pv.vec, offset);
    offset += pv.vec.length;
  }
  buf.set(query, offset);
  return new Uint8Array(buf.buffer);
}

// ── Pinning helper (run with: bun src/memory-palace/fixtures/knn-parity.ts) ─
if (typeof process !== 'undefined' && process.argv[1]?.endsWith('knn-parity.ts')) {
  const { createHash } = await import('crypto');
  const fixture = generateFixture(100, 256, 42);
  const query = generateQueryVector(256, 43);
  const bytes = fixtureBytes(fixture, query);
  const hash = createHash('sha256').update(bytes).digest('hex');
  console.log('Fixture SHA-256:', hash);
  console.log('Total bytes:', bytes.length);
  console.log('Matches FIXTURE_SHA256_HEX:', hash === FIXTURE_SHA256_HEX);
}
