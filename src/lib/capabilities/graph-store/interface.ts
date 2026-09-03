/**
 * graph-store/1 — capability interface (conformance core).
 *
 * The graph store is a Category-B (stateful service) capability
 * (docs/decisions/2026-05-31-capability-provider-model.md §4). Its full
 * authoritative surface is the palace's existing **StoreAPI**
 * (`src/memory-palace/store-types.ts`) — already the engine swap boundary
 * per D-007/TC12 ("@ladybugdb/core and kuzu-wasm MUST NOT be imported outside
 * store.server.ts/store.browser.ts; this interface is the swap boundary").
 *
 * This file is the **conformance core** of that surface: lifecycle +
 * containment + the signed-action-log replay primitive (D-021/D-028 — the
 * graph is a derived index over the action log). A provider that passes the
 * `graph-store/1` conformance suite (./conformance.ts) is a valid provider,
 * regardless of engine — kuzu, LadybugDB, SQLite, or the in-memory reference.
 * That is the whole point of the interface: it is the *query/replay surface*,
 * not the engine.
 *
 * Increment 1 implements this core in-memory + conformance + registration so
 * the resolver binds `service/graph-store`. Later increments widen the core
 * toward the full StoreAPI and add the ladybug-napi / ladybug-wasm+OPFS
 * providers (see docs/decisions/2026-05-31-browser-graph-store-opfs.md).
 */

// Node summaries. `fp` + structure are the graph-store's responsibility; `name`
// is best-effort only — names live in the signed envelope/CAS, so a real engine
// (ServerStore) returns it undefined. Conformance never asserts `name`.
export interface PalaceData {
  readonly fp: string;
  readonly name?: string;
}

export interface RoomData {
  readonly fp: string;
  readonly name?: string;
}

/** Subset of StoreAPI's RecordActionParams used by the replay core. */
export interface RecordActionParams {
  /** Blake3 fp of the signed action envelope (the ActionLog primary key). */
  readonly fp: string;
  readonly palaceFp: string;
  readonly actionKind: string;
  readonly actorFp: string;
  /** Target node fp, if any. */
  readonly targetFp?: string | null;
  /** Parent action fps — the DAG edges (ACKS). */
  readonly parentHashes: readonly string[];
  /** ms-epoch timestamp. */
  readonly timestamp: number;
}

/** One ActionLog row as returned by `actionsSince`. */
export interface ActionRow {
  readonly fp: string;
  readonly actionKind: string;
  readonly targetFp: string;
  readonly timestamp: number;
}

/**
 * `graph-store/1` conformance core. Implemented by every graph-store provider.
 * Method names + semantics mirror StoreAPI so a full provider is a superset.
 */
export interface GraphStore {
  /** Open the store (idempotent). Must precede any other verb. */
  open(): Promise<void>;
  /** Close the store. */
  close(): Promise<void>;

  /** Ensure a Palace node exists (idempotent/MERGE). `name` is best-effort (see
   *  the node-summaries note above) — not a contract guarantee. */
  ensurePalace(fp: string, opts?: { name?: string }): Promise<void>;
  /** Add a Room inside a Palace (Room node + containment). */
  addRoom(palaceFp: string, roomFp: string, opts?: { name?: string }): Promise<void>;
  /** Palace summary, or null if absent. */
  getPalace(palaceFp: string): Promise<PalaceData | null>;
  /** Rooms in a palace, sorted by fp (stable). */
  roomsFor(palaceFp: string): Promise<RoomData[]>;

  /** Append a signed action to the log (upsert on fp — replay-idempotent). */
  recordAction(params: RecordActionParams): Promise<void>;
  /** DAG tips: action fps referenced by no other action's parentHashes. */
  headHashes(palaceFp: string): Promise<string[]>;
  /** Replay: actions with timestamp strictly after the cursor (0/absent = all). */
  actionsSince(palaceFp: string, opts?: { afterTimestamp?: number }): Promise<ActionRow[]>;
}
