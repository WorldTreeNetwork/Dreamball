/**
 * graph-store-ladybug.ts — the `ladybug-napi` graph-store/1 provider.
 *
 * Wraps the palace's ServerStore (@ladybugdb/core napi) as a graph-store/1
 * provider. It lives here (NOT in the capability package) because TC12 confines
 * the @ladybugdb import to the store layer — this adapter imports ServerStore,
 * keeping the engine dependency inside src/memory-palace. It implements the
 * SHARED graph-store/1 interface (src/lib/capabilities/graph-store), so the
 * resolver binds it like any other provider and the conformance suite runs
 * against it unchanged.
 *
 * graph-store/1 is the conformance CORE of ServerStore's full StoreAPI, so this
 * mostly delegates 1:1. The only mappings: ensurePalace drops the in-memory-only
 * `name` opt (ServerStore sources names from the envelope/CAS, not the node),
 * and the readonly parentHashes is copied to a mutable array for ServerStore.
 */

import { ServerStore } from './store.server.js';
import type {
  GraphStore,
  PalaceData,
  RoomData,
  RecordActionParams,
  ActionRow,
} from '../lib/capabilities/graph-store/interface.js';

export class LadybugGraphStore implements GraphStore {
  readonly id = 'ladybug-napi';
  readonly implementsVersion = '1.0';

  constructor(private readonly store: ServerStore) {}

  open(): Promise<void> {
    return this.store.open();
  }
  close(): Promise<void> {
    return this.store.close();
  }
  ensurePalace(fp: string): Promise<void> {
    return this.store.ensurePalace(fp);
  }
  addRoom(palaceFp: string, roomFp: string): Promise<void> {
    return this.store.addRoom(palaceFp, roomFp);
  }
  getPalace(palaceFp: string): Promise<PalaceData | null> {
    return this.store.getPalace(palaceFp);
  }
  roomsFor(palaceFp: string): Promise<RoomData[]> {
    return this.store.roomsFor(palaceFp);
  }
  recordAction(params: RecordActionParams): Promise<void> {
    return this.store.recordAction({ ...params, parentHashes: [...params.parentHashes] });
  }
  headHashes(palaceFp: string): Promise<string[]> {
    return this.store.headHashes(palaceFp);
  }
  actionsSince(palaceFp: string, opts?: { afterTimestamp?: number }): Promise<ActionRow[]> {
    return this.store.actionsSince(palaceFp, opts);
  }
}

/** Build a ladybug-napi graph-store provider (defaults to an in-memory DB). */
export function makeLadybugGraphStore(dbPath = ':memory:'): LadybugGraphStore {
  return new LadybugGraphStore(new ServerStore(dbPath));
}
