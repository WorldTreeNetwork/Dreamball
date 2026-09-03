/**
 * truncate.ts — MRL prefix truncation for the `text-embed/1` capability.
 *
 * Previously lived in `embedding/qwen3.ts` alongside the in-process ONNX
 * runtime. It is not a property of any one provider: every provider bound to
 * `text-embed/1` declares a `nativeDim`, and the resolver normalizes that to
 * the interface's `OUTPUT_DIM` through this single path. So it belongs to the
 * capability, not to a model adapter — which is why it survived the removal of
 * the in-process provider (see
 * docs/decisions/2026-08-07-substrate-palace-boundary.md).
 *
 * MRL semantics: Matryoshka-Representation-Learning-trained models (the
 * declared MODEL_IDENTITY is qwen3-embedding-0.6b) produce vectors whose first
 * N dimensions are themselves a semantically valid N-dimensional embedding. We
 * always take the FIRST N dims — not the last, not a random projection, not
 * normalized. See D-002 and Epic 6 AC3.
 */

/**
 * Take the first `dim` dimensions of a full-length embedding vector.
 *
 * This is the sole truncation path: every embedding that leaves
 * dreamball-server must pass through here (AC3).
 *
 * @param vec  Full-length embedding (1024d for the GPU providers, 256d mock)
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
