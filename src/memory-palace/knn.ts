/**
 * knn.ts — High-level `kNN(query, k)` domain function (S6.3 / D-007).
 *
 * This module is the SOLE caller of `store.kNN(vec, k)` (the low-level
 * adapter verb). All epic code (oracle, file-watcher, resonance UI) calls
 * `kNN(store, query, k)` from here — not the adapter method directly (D-007).
 *
 * Flow:
 *   1. Call `embedFor(query, 'text/plain', embedViaUrl)` to embed the query
 *      string into a 256d Float32Array via the /embed endpoint (D-012).
 *      ← TODO-EMBEDDING marker is here (AC7): the sole network exit in kNN.
 *   2. Call `store.kNN(vec, k)` — local QUERY_VECTOR_INDEX (no network exit).
 *   3. Return `KnnHit[]` with { fp, roomFp, distance }.
 *
 * Offline contract (AC4, AC5, NFR11):
 *   - If embedFor throws EmbeddingServiceUnreachable, re-throw as OfflineKnnError.
 *   - NEVER return a resolved Promise with stale results.
 *   - `OfflineKnnError.cached` is always [] — consumer epics (Epic 4, Epic 5)
 *     decide what to show when offline.
 *
 * AC7: TODO-EMBEDDING marker is directly above the `embedFor` call — NOT at
 *   the vector-index lookup (that's local; no network exit to mark).
 *
 * AC6 cross-runtime routing:
 *   - Server (Bun + @ladybugdb/core): store.kNN uses native QUERY_VECTOR_INDEX.
 *   - Browser (kuzu-wasm): D-015 parity PASS (set-equal, max|Δ|=0.000048) →
 *     KNN_LOCAL=true → local QUERY_VECTOR_INDEX. HTTP fallback preserved as
 *     TODO-KNN-FALLBACK in store.browser.ts; not active.
 *   The routing decision is runtime (store adapter selected by the caller);
 *   this function is runtime-agnostic.
 *
 * Decisions: D-007 (domain verb), D-012 (single POST wire shape),
 *            D-015 (cross-runtime parity outcome), D-016 (Cypher pattern).
 * NFRs: NFR10 (<200ms p50 on 500-inscription corpus — R5 mitigation),
 *       NFR11 (offline graceful-degradation), NFR13, NFR15.
 * SEC: SEC6, SEC7.
 */

import { type StoreAPI, type KnnHit, OfflineKnnError } from './store-types.js';
import { embedFor, EmbeddingServiceUnreachable } from './embedding-client.js';

export { OfflineKnnError } from './store-types.js';
export type { KnnHit } from './store-types.js';

// Default embed endpoint — same as embedding-client.ts default (D-012).
const DEFAULT_EMBED_URL = 'http://localhost:9808/embed';

/**
 * High-level K-nearest-neighbour query (S6.3 domain function).
 *
 * @param store        Open StoreAPI adapter (server or browser).
 * @param query        Query text to embed (D-012 content field).
 * @param k            Number of nearest neighbours to return.
 * @param embedViaUrl  Full URL of the /embed endpoint (default: localhost:9808).
 * @returns            Top-k KnnHit[] sorted by cosine distance ASC.
 * @throws OfflineKnnError when embedding service is unreachable (AC4, AC5).
 */
export async function kNN(
  store: StoreAPI,
  query: string,
  k: number,
  embedViaUrl = DEFAULT_EMBED_URL
): Promise<KnnHit[]> {
  // TODO-EMBEDDING: bring-model-local-or-byo
  //   This call is the SOLE network exit for kNN (NFR11 sanctioned exit).
  //   The /embed endpoint is the query-embedding step; it is NOT the vector-index
  //   lookup (which is local). Replace with a local WASM/ONNX call when weights
  //   are bundled locally.
  let vector: number[];
  try {
    vector = await embedFor(query, 'text/plain', embedViaUrl);
  } catch (err) {
    if (err instanceof EmbeddingServiceUnreachable) {
      // AC4, AC5: typed throw — never resolve with stale results.
      throw new OfflineKnnError(err);
    }
    throw err;
  }

  const vec = new Float32Array(vector);

  // Local QUERY_VECTOR_INDEX (no network exit — no TODO-EMBEDDING here per AC7).
  const rows = await store.kNN(vec, k);

  return rows.map((r) => ({
    fp: r.fp,
    roomFp: r.roomFp,
    distance: r.distance,
  }));
}
