/**
 * graph-store-ladybug.test.ts — proves the REAL LadybugDB engine (ServerStore,
 * @ladybugdb/core napi) satisfies the SAME `graph-store/1` conformance suite that
 * the in-memory reference passes. Two unrelated engines, one contract ⇒
 * graph-store/1 is genuinely engine-agnostic (decision-doc §8 thesis), not an
 * artifact of the toy reference impl.
 *
 * Runs ServerStore against an in-memory (':memory:') LadybugDB; open() loads the
 * VECTOR extension (present in this environment — the in-memory provider is the
 * Dreamball-7bc degraded path for when it is not). The adapter maps graph-store/1
 * onto ServerStore's StoreAPI: ensurePalace drops the in-memory-only `name` opt,
 * and the readonly parentHashes is copied to a mutable array.
 */

import { describe, it, expect } from 'vitest';
import { runGraphStoreConformance } from '../../jelly-server/src/capabilities/graph-store/conformance.js';
import type { GraphStore } from '../../jelly-server/src/capabilities/graph-store/interface.js';
import { ServerStore } from '../../src/memory-palace/store.server.js';

function adaptServerStore(s: ServerStore): GraphStore {
  return {
    open: () => s.open(),
    close: () => s.close(),
    ensurePalace: (fp) => s.ensurePalace(fp),
    addRoom: (palaceFp, roomFp) => s.addRoom(palaceFp, roomFp),
    getPalace: (fp) => s.getPalace(fp),
    roomsFor: (fp) => s.roomsFor(fp),
    recordAction: (p) => s.recordAction({ ...p, parentHashes: [...p.parentHashes] }),
    headHashes: (fp) => s.headHashes(fp),
    actionsSince: (fp, opts) => s.actionsSince(fp, opts),
  };
}

describe('graph-store/1 conformance — LadybugDB (ServerStore) engine', () => {
  it('the real @ladybugdb/core engine satisfies the same suite as in-memory', async () => {
    const result = await runGraphStoreConformance(() => adaptServerStore(new ServerStore(':memory:')));
    const failed = result.checks.filter((c) => !c.pass);
    expect(failed, JSON.stringify(failed, null, 2)).toEqual([]);
    expect(result.ok).toBe(true);
  });
});
