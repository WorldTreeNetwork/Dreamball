/**
 * graph-store-ladybug.test.ts — proves the REAL LadybugDB engine satisfies the
 * SAME `graph-store/1` conformance suite as the in-memory reference. Two unrelated
 * engines, one contract ⇒ graph-store/1 is genuinely engine-agnostic (decision-doc
 * §8 thesis), not an artifact of the toy reference impl.
 *
 * Exercises the real `ladybug-napi` provider (src/memory-palace/graph-store-ladybug.ts,
 * wrapping ServerStore / @ladybugdb/core napi) against an in-memory (':memory:')
 * LadybugDB. open() loads the VECTOR extension (present in this environment — the
 * in-memory provider is the Dreamball-7bc degraded path for when it is not).
 */

import { describe, it, expect } from 'vitest';
import { runGraphStoreConformance } from '../../src/lib/capabilities/graph-store/conformance.js';
import { makeLadybugGraphStore } from '../../src/memory-palace/graph-store-ladybug.js';

describe('graph-store/1 conformance — LadybugDB (ladybug-napi provider)', () => {
  it('the real @ladybugdb/core engine satisfies the same suite as in-memory', async () => {
    const result = await runGraphStoreConformance(() => makeLadybugGraphStore(':memory:'));
    const failed = result.checks.filter((c) => !c.pass);
    expect(failed, JSON.stringify(failed, null, 2)).toEqual([]);
    expect(result.ok).toBe(true);
  });
});
