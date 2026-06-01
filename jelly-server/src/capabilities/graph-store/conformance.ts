/**
 * conformance.ts — the `graph-store/1` conformance suite.
 *
 * This is the **enforced-semver enforcement** made real for one interface
 * (docs/decisions/2026-05-31-capability-provider-model.md §10.1): a provider's
 * `implements: service/graph-store@1.x` claim is only honest if it passes this
 * suite. It is engine-neutral — hand it a factory for any GraphStore (in-memory,
 * ladybug, sqlite) and it exercises the same contract.
 *
 * Pure (no test-framework dependency): it returns a ConformanceResult; the test
 * harness asserts on it. `runGraphStoreConformance(make).ok === true` is the
 * machine-checkable form of "this engine satisfies graph-store/1".
 */

import type { GraphStore } from './interface.js';

export interface ConformanceCheck {
  readonly name: string;
  readonly pass: boolean;
  readonly detail?: string;
}

export interface ConformanceResult {
  readonly ok: boolean;
  readonly checks: readonly ConformanceCheck[];
}

const fp = (b: string): string => b.repeat(32);

export async function runGraphStoreConformance(
  make: () => GraphStore,
): Promise<ConformanceResult> {
  const checks: ConformanceCheck[] = [];
  const check = (name: string, pass: boolean, detail?: string): void => {
    checks.push({ name, pass, detail: pass ? undefined : detail });
  };

  const store = make();
  await store.open();
  try {
    const P = fp('aa');

    // ── Containment ───────────────────────────────────────────────────────────
    await store.ensurePalace(P, { name: 'Test Palace' });
    const pd = await store.getPalace(P);
    check('ensurePalace + getPalace round-trips', pd?.fp === P && pd?.name === 'Test Palace', JSON.stringify(pd));
    check('getPalace returns null for unknown fp', (await store.getPalace(fp('00'))) === null);

    await store.ensurePalace(P, { name: 'ignored-second-write' });
    check('ensurePalace is idempotent (first-write-wins)', (await store.getPalace(P))?.name === 'Test Palace');

    const R1 = fp('bb');
    const R2 = fp('11');
    await store.addRoom(P, R1, { name: 'Library' });
    await store.addRoom(P, R2, { name: 'Forge' });
    const rooms = await store.roomsFor(P);
    check('roomsFor returns all rooms', rooms.length === 2, `len=${rooms.length}`);
    check('roomsFor is sorted by fp', rooms.length === 2 && rooms[0].fp < rooms[1].fp, rooms.map((r) => r.fp).join(','));
    check('roomsFor is empty for a roomless palace', (await store.roomsFor(fp('00'))).length === 0);

    // ── Action-log replay (D-021/D-028) ───────────────────────────────────────
    const A = fp('a0');
    const B = fp('b0');
    const C = fp('c0');
    await store.recordAction({ fp: A, palaceFp: P, actionKind: 'palace-minted', actorFp: P, parentHashes: [], timestamp: 100 });
    await store.recordAction({ fp: B, palaceFp: P, actionKind: 'room-added', actorFp: P, targetFp: R1, parentHashes: [A], timestamp: 200 });
    await store.recordAction({ fp: C, palaceFp: P, actionKind: 'room-added', actorFp: P, targetFp: R2, parentHashes: [B], timestamp: 300 });

    const heads = await store.headHashes(P);
    check('headHashes returns the single DAG tip', heads.length === 1 && heads[0] === C, heads.join(','));

    const D = fp('d0');
    await store.recordAction({ fp: D, palaceFp: P, actionKind: 'move', actorFp: P, parentHashes: [B], timestamp: 350 });
    const heads2 = await store.headHashes(P);
    check('headHashes returns both concurrent tips', heads2.length === 2 && heads2.includes(C) && heads2.includes(D), heads2.join(','));

    // replaying A is a no-op (idempotent on fp)
    await store.recordAction({ fp: A, palaceFp: P, actionKind: 'palace-minted', actorFp: P, parentHashes: [], timestamp: 100 });
    const all = await store.actionsSince(P, { afterTimestamp: 0 });
    check('recordAction is idempotent on fp (no duplicates)', all.length === 4, `len=${all.length}`);
    check('actionsSince returns rows in timestamp order', all.map((a) => a.timestamp).join(',') === '100,200,300,350', all.map((a) => a.timestamp).join(','));

    const since = await store.actionsSince(P, { afterTimestamp: 200 });
    check('actionsSince(afterTimestamp) is exclusive', since.length === 2 && since.every((a) => a.timestamp > 200), since.map((a) => a.timestamp).join(','));

    check('actionsSince is empty for an unknown palace', (await store.actionsSince(fp('00'))).length === 0);
  } finally {
    await store.close();
  }

  return { ok: checks.every((c) => c.pass), checks };
}
