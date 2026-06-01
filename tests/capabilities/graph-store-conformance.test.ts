/**
 * graph-store-conformance.test.ts — proves the in-memory engine satisfies
 * `graph-store/1` (jelly-server/src/capabilities/graph-store/).
 *
 * This is the engine-independence thesis made executable: a non-kuzu engine
 * passes the same conformance suite, so it is a valid `service/graph-store`
 * provider. The suite is reusable — the ladybug-napi / OPFS providers (later
 * increments) run the identical checks.
 */

import { describe, it, expect } from 'vitest';
import { runGraphStoreConformance } from '../../jelly-server/src/capabilities/graph-store/conformance.js';
import { InMemoryGraphStore } from '../../jelly-server/src/capabilities/graph-store/providers/in-memory.js';

describe('graph-store/1 conformance — in-memory reference provider', () => {
  it('passes every conformance check (engine-agnostic contract)', async () => {
    const result = await runGraphStoreConformance(() => new InMemoryGraphStore());
    const failed = result.checks.filter((c) => !c.pass);
    expect(failed, JSON.stringify(failed, null, 2)).toEqual([]);
    expect(result.ok).toBe(true);
    // sanity: the suite ran a meaningful number of checks
    expect(result.checks.length).toBeGreaterThanOrEqual(10);
  });

  it('rejects verbs before open() (lifecycle guard)', async () => {
    const s = new InMemoryGraphStore();
    await expect(s.getPalace('00'.repeat(32))).rejects.toThrow(/open\(\)/);
  });
});
