/**
 * parity-ground-truth.ts — single source of truth for K-NN parity ground truth.
 *
 * Sprint-1 code review MEDIUM-3: factor out the SERVER_GROUND_TRUTH array
 * that was previously inlined in tests/parity-browser.e2e.ts and computed
 * independently in src/memory-palace/parity.test.ts. Both tests now import
 * from this module so there is ONE source of truth.
 *
 * Recorded: 2026-04-22 by S2.1 vitest server test (parity.test.ts AC2).
 * To refresh: re-run `bun run test:unit -- --run --project=server` and
 * update the array below with the new ground-truth values.
 */

export interface KnnRow {
  fp: string;
  distance: number;
}

/**
 * Top-10 server ground truth from @ladybugdb/core with seed=42 fixture
 * (100 vectors, dim=256) and query vector seed=43, k=10.
 */
export const SERVER_GROUND_TRUTH: KnnRow[] = [
  { fp: 'v79', distance: 0.7617 },
  { fp: 'v18', distance: 0.8787 },
  { fp: 'v31', distance: 0.8877 },
  { fp: 'v32', distance: 0.8938 },
  { fp: 'v1',  distance: 0.8952 },
  { fp: 'v28', distance: 0.8985 },
  { fp: 'v33', distance: 0.9018 },
  { fp: 'v66', distance: 0.9029 },
  { fp: 'v44', distance: 0.9133 },
  { fp: 'v60', distance: 0.9176 },
];
