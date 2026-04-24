/**
 * store-types.ts — Explicit StoreAPI contract (D-007, TC12)
 *
 * This interface is the SOLE contract that all palace-state consumers depend on.
 * Server adapter: store.server.ts
 * Browser adapter: store.browser.ts (S2.3)
 *
 * TC12: @ladybugdb/core and kuzu-wasm MUST NOT be imported outside store.server.ts /
 * store.browser.ts. This interface is the swap boundary.
 *
 * TC13: No CBOR bytes stored in the DB — every fp argument is a Blake3 hex string.
 *
 * Vector verbs (reembed, deleteEmbedding, upsertEmbedding, kNN) are declared
 * here for interface completeness. S2.2 stubs them with TODO-EMBEDDING markers.
 * S2.5 provides real implementations.
 */

// ── Palace / Room read types (S5.2 — PalaceLens consumer) ────────────────────

/**
 * Decoded palace room as returned by `roomsFor`.
 *
 * `layout` carries the `jelly.layout` envelope for the room if present;
 * its `placements` array maps child-fp → [x,y,z] + quaternion. When absent
 * (null), the lens falls back to the deterministic-grid algorithm (AC3).
 *
 * Coords: position is cartesian local-to-field-origin (ADR 2026-04-24-coord-frames §2).
 */
export interface RoomData {
  /** Blake3 fp identifying this room. */
  fp: string;
  /** Optional display name. */
  name?: string;
  /** Decoded jelly.layout for this room, or null when absent. */
  layout: {
    placements: Array<{
      'child-fp': string;
      position: [number, number, number];
      facing: [number, number, number, number];
    }>;
  } | null;
}

/**
 * Palace summary as returned by `getPalace`.
 *
 * The palace envelope itself is a `jelly.dreamball.field`; here we
 * surface just the fields the lens needs to render the outer shell.
 */
export interface PalaceData {
  /** Blake3 fp of the palace (field envelope). */
  fp: string;
  /** Optional display name. */
  name?: string;
  /**
   * Omnispherical grid — if present gives pole-north / pole-south /
   * camera-ring / layer-depth for the outer shell topology.
   * Null when the field has no grid attribute (grid-less palace).
   */
  omnisphericalGrid: {
    'pole-north'?: { x: number; y: number; z: number };
    'pole-south'?: { x: number; y: number; z: number };
    'camera-ring'?: Array<{ radius: number; tilt: number; fov: number }>;
    'layer-depth'?: number;
    resolution?: number;
  } | null;
}

// ── Room contents types (S5.3 — RoomLens consumer) ───────────────────────────

/**
 * A single inscription item returned by `roomContents(roomFp)`.
 *
 * `placement` carries cartesian position + quaternion facing when the room's
 * `jelly.layout` specifies it; null when absent → lens uses deterministic grid
 * fallback (AC2). Coords are local-to-room-origin per ADR 2026-04-24-coord-frames §2.
 *
 * `surface` is the inscription's render surface tag (e.g. "scroll", "tablet")
 * for use by InscriptionLens in S5.4.
 */
export interface RoomContentsItem {
  /** Blake3 fp of the inscription / avatar. */
  fp: string;
  /** Optional display name. */
  name?: string;
  /** Surface tag for InscriptionLens dispatch (S5.4). */
  surface?: string;
  /**
   * Cartesian position [x,y,z] and quaternion facing [qx,qy,qz,qw] local to the
   * room origin. Null when jelly.layout does not specify a placement for this item.
   *
   * Quaternion order: [qx, qy, qz, qw] per glTF 2.0 / ADR 2026-04-24-coord-frames.
   */
  placement: {
    position: [number, number, number];
    facing: [number, number, number, number];
  } | null;
}

// ── Policy-gated read types (S4.2) ───────────────────────────────────────────

/** Data returned by getInscription (policy-gated read verb). */
export interface InscriptionData {
  fp: string;
  source_blake3: string;
  orphaned: boolean;
  created_at: number;
  /** Policy slot kind: 'public' or 'any-admin'. Defaults to 'public'. */
  policy?: 'public' | 'any-admin';
  /** Revision counter — incremented by file-watcher on every source edit. */
  revision?: number;
}

/**
 * Public metadata for InscriptionLens dispatch (S5.4 / ADR 2026-04-24-surface-registry).
 *
 * Not policy-gated — `surface` is an open-enum display attribute on the envelope
 * and the fallback chain is part of the render contract. The body bytes go through
 * the policy-gated path (`getInscription` + `inscriptionBody`).
 */
export interface InscriptionMeta {
  /** Blake3 fp of the inscription. */
  fp: string;
  /** Surface tag (open-enum, default 'scroll' when absent). */
  surface: string;
  /**
   * Author-attached fallback chain per ADR 2026-04-24-surface-registry §4.
   * Empty array when the envelope carries no fallback attribute.
   */
  fallback: string[];
}

// ── Write context (S4.2 AC5 / SEC5 file-watcher gate) ────────────────────────

/**
 * Per-call write-context for mutation verbs. Consumed by the store's
 * `_gateWrite` hook which delegates to `evaluateWritePolicy`.
 *
 * Default context is `{ requesterFp: '', origin: 'custodian' }`. Anonymous
 * (empty-string) requesterFp bypasses the gate — that branch is reserved for
 * custodian-authenticated callers whose identity is proven upstream by Zig.
 *
 * Only the file-watcher skill may set `origin: 'file-watcher'`, which is the
 * sole legitimate path for oracle-fp writes (SEC5).
 */
export interface WriteContext {
  /** fp of the agent performing the write; '' = anonymous custodian (default). */
  requesterFp: string;
  /** Origin of the write. Only 'file-watcher' permits oracle-fp writes. */
  origin: 'file-watcher' | 'custodian' | 'stranger';
}

/** One triple from the mythos chain. */
export interface MythosTriple {
  subject: string;
  predicate: string;
  object: string;
}

// ── Action kinds (RC2 — 9 known kinds) ───────────────────────────────────────

export type ActionKind =
  | 'palace-minted'
  | 'room-added'
  | 'avatar-inscribed'
  | 'aqueduct-created'
  | 'move'
  | 'true-naming'
  | 'inscription-updated'
  | 'inscription-orphaned'
  | 'inscription-pending-embedding';

// ── recordAction payload ──────────────────────────────────────────────────────

export interface RecordActionParams {
  /** Blake3 fp of the signed action envelope (PK for ActionLog) */
  fp: string;
  /** Palace this action belongs to */
  palaceFp: string;
  /** One of the 9 known action kinds */
  actionKind: ActionKind | string;
  /** Agent who authored the action */
  actorFp: string;
  /** Target node fp (room, inscription, etc.) — null if action has no target */
  targetFp?: string | null;
  /** Parent action fps (DAG edges) */
  parentHashes: string[];
  /** Optional logical dependencies */
  deps?: string[];
  /** Optional invalidations */
  nacks?: string[];
  /** ISO-8601 or ms-epoch timestamp */
  timestamp: Date | number | string;
  /** Blake3 of the raw CBOR envelope — TC13: pointer only, not the bytes */
  cborBytesBlake3?: string;
}

// ── recordTraversal payload (S5.5 — FR18 renderer half) ─────────────────────

/**
 * Input for store.recordTraversal — triggered by PalaceLens navigate events.
 *
 * fromFp and toFp are room fps; the palaceFp is the containing palace. The
 * optional actorFp is the agent performing the traversal (defaults to the
 * palace fp — matches the palace-minted "wandering custodian" convention used
 * by the Zig CLI when no explicit actor is passed).
 *
 * timestamp_ms defaults to Date.now() if absent; tests pass explicit values
 * for determinism.
 */
export interface RecordTraversalParams {
  /** Blake3 fp of the palace containing the two rooms. */
  palaceFp: string;
  /** Blake3 fp of the source room. */
  fromFp: string;
  /** Blake3 fp of the destination room. */
  toFp: string;
  /** Blake3 fp of the actor performing the traversal. Default: palaceFp. */
  actorFp?: string;
  /** ms-epoch timestamp. Default: Date.now(). */
  timestamp?: number;
}

/**
 * Output of store.recordTraversal — the sequenced result the renderer uses
 * to paint the traversal arc (SEC11 — renderer waits until this resolves).
 */
export interface RecordTraversalResult {
  /** Blake3 fp of the move ActionLog entry (persisted). */
  moveActionFp: string;
  /** True iff a new aqueduct was materialised during this traversal. */
  aqueductCreated: boolean;
  /** Blake3 fp of the aqueduct (new or pre-existing). */
  aqueductFp: string;
  /** Aqueduct strength AFTER the Hebbian update (TC17 monotone). */
  newStrength: number;
  /** Aqueduct conductance AFTER Ebbinghaus/Hebbian update. */
  newConductance: number;
  /** Revision counter AFTER the update (incremented). */
  newRevision: number;
  /** Timestamp persisted with the move action. */
  timestamp: number;
}

// ── StoreAPI ──────────────────────────────────────────────────────────────────

export interface StoreAPI {
  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /**
   * Open the store: load DB, run DDL, load VECTOR extension.
   * Must be called before any other verb.
   * Idempotent: safe to call if already open (returns immediately).
   */
  open(): Promise<void>;

  /**
   * Close the store: close Connection then Database, ensuring all
   * QueryResult handles are closed first (TC9).
   */
  close(): Promise<void>;

  /**
   * Sync the in-memory FS to/from persistent storage.
   * Direction 'in' = load from storage; 'out' = flush to storage.
   *
   * SERVER: no-op (resolves within 1 ms) — AC7.
   * BROWSER (S2.3): calls FS.syncfs(direction === 'in').
   */
  syncfs(direction: 'in' | 'out'): Promise<void>;

  // ── Containment verbs ─────────────────────────────────────────────────────

  /**
   * Ensure a Palace node exists with the given fp.
   * Idempotent: MERGE semantics — creates if absent, no-ops if present.
   */
  ensurePalace(
    fp: string,
    mythosHeadFp?: string,
    opts?: { formatVersion?: number; revision?: number }
  ): Promise<void>;

  /**
   * Add a Room inside a Palace.
   * Creates Room node + CONTAINS edge from Palace.
   */
  addRoom(
    palaceFp: string,
    roomFp: string,
    opts?: { name?: string; archiform?: string }
  ): Promise<void>;

  /**
   * Inscribe an Avatar (Inscription node) inside a Room.
   * Creates Inscription node + CONTAINS edge from Room + LIVES_IN edge to Room.
   * source_blake3 is RC3 canonical (not body_hash).
   */
  inscribeAvatar(
    roomFp: string,
    avatarFp: string,
    sourceBlake3: string,
    opts?: { surface?: string; embedding?: Float32Array | null; archiform?: string }
  ): Promise<void>;

  // ── Mythos-chain verbs ────────────────────────────────────────────────────

  /**
   * Set (or replace) the MYTHOS_HEAD edge from a Palace to a Mythos node.
   * If the Mythos node does not yet exist it is created.
   * Removes any prior MYTHOS_HEAD edge first.
   */
  setMythosHead(
    palaceFp: string,
    mythosFp: string,
    opts?: { actionFp?: string; isGenesis?: boolean; bodyHash?: string }
  ): Promise<void>;

  /**
   * Append a new Mythos entry in the chain by creating a PREDECESSOR edge
   * from newFp → predecessorFp. Creates the newFp Mythos node if absent.
   */
  appendMythos(
    newFp: string,
    predecessorFp: string,
    opts?: { bodyHash?: string; trueName?: string; discoveredInActionFp?: string }
  ): Promise<void>;

  /**
   * Return the fp of the current MYTHOS_HEAD Mythos node for the palace,
   * or null if no head is set.
   */
  getMythosHead(palaceFp: string): Promise<string | null>;

  // ── Action log (commit-log table) ─────────────────────────────────────────

  /**
   * Write a row to the ActionLog node-table.
   * Per D-016: ActionLog is a node-table, not a node-label.
   * No Action node label must exist (AC4).
   */
  recordAction(params: RecordActionParams): Promise<void>;

  /**
   * Return the set of action fps that are DAG tips for the palace —
   * i.e. fps that appear in no other row's parent_hashes for this palace.
   * These are the "head hashes" per PROTOCOL §13.3.
   */
  headHashes(palaceFp: string): Promise<string[]>;

  // ── Vector verbs (surface only — S2.5 implements) ─────────────────────────

  /**
   * Upsert an embedding vector for an Inscription.
   * @throws NotImplementedInS22 until S2.5 ships.
   * TODO-EMBEDDING: implement in S2.5
   */
  upsertEmbedding(fp: string, vec: Float32Array): Promise<void>;

  /**
   * Delete the embedding column for an Inscription (sets to NULL).
   * @throws NotImplementedInS22 until S2.5 ships.
   * TODO-EMBEDDING: implement in S2.5
   */
  deleteEmbedding(fp: string): Promise<void>;

  /**
   * Delete-then-insert vector write as the FR21 sole vector-write path.
   * @throws NotImplementedInS22 until S2.5 ships.
   * TODO-EMBEDDING: implement in S2.5
   */
  reembed(fp: string, newBytes: Uint8Array, newVec: Float32Array): Promise<void>;

  /**
   * K-nearest-neighbour query over Inscription.embedding.
   * @throws NotImplementedInS22 until S2.5 ships.
   * TODO-EMBEDDING: implement in S2.5
   */
  kNN(
    vec: Float32Array,
    k: number,
    filter?: { palaceFp?: string; roomFp?: string }
  ): Promise<Array<{ fp: string; distance: number }>>;

  // ── Aqueduct helpers (S2.5 — FR26 / AC10) ────────────────────────────────

  /**
   * Lazily create an Aqueduct between two rooms if none exists (D-003).
   * Returns the aqueduct fp. Idempotent: returns existing fp if already present.
   */
  getOrCreateAqueduct(
    fromRoomFp: string,
    toRoomFp: string,
    palaceFp: string
  ): Promise<string>;

  /**
   * Update an aqueduct's strength (Hebbian), conductance (Ebbinghaus), and
   * revision after a traversal. Resistance and capacitance are NEVER overwritten
   * by the runtime (AC10 invariant — these are signed, not computed).
   */
  updateAqueductStrength(
    aqueductFp: string,
    actorFp: string,
    timestamp: number
  ): Promise<void>;

  // ── Traversal round-trip (S5.5 — FR18 renderer half, D-007 CRITICAL) ─────

  /**
   * Record a room → room traversal in a single logical transaction.
   *
   * Flow (all within one logical tx — SEC11 ordering):
   *   1. Look up (or lazily create) the aqueduct between fromFp and toFp via
   *      getOrCreateAqueduct. First-traversal side-effects: a jelly.aqueduct
   *      row with D-003 defaults (resistance=0.3, capacitance=0.5, strength=0,
   *      kind="visit") AND a paired aqueduct-created ActionLog entry (both
   *      derived fps — replay-reproducible, no timestamps in the fp).
   *   2. Update Hebbian strength via updateAqueductStrength — TC17 monotone.
   *   3. Emit a `move` signed-action via recordAction; the ActionLog fp is
   *      derived from (fromFp, toFp, timestamp, palaceFp). Dual ed25519 +
   *      ML-DSA-87 signatures are authored by the caller and carried in the
   *      cbor_bytes_blake3 pointer (TC13); the MVP stub stores the derived fp
   *      as the cbor_bytes_blake3 pointer until the Zig-side WASM signer
   *      parameterisation lands (known-gaps §6 — TODO-CRYPTO).
   *   4. Return a sequenced tuple describing what happened so the renderer
   *      can only paint the traversal arc after the action's Blake3 has
   *      persisted (SEC11 ordering — renderer awaits the returned promise).
   *
   * Preconditions:
   *   - Palace, fromRoom, and toRoom MUST exist in the graph. Missing rooms
   *     throw — the caller must ensure rooms were added via addRoom first.
   *
   * D-007: this is the SOLE traversal-event entry point from lens code. Lenses
   * dispatch `navigate` CustomEvents; the viewer calls this verb; no lens
   * writes to LadybugDB or CAS directly (SEC11).
   *
   * @param params  Traversal parameters.
   * @returns       Sequenced result the renderer uses to paint the arc.
   */
  recordTraversal(params: RecordTraversalParams): Promise<RecordTraversalResult>;

  // ── Oracle KG triple verbs (S4.3 — D-007 domain verbs) ───────────────────

  /**
   * Insert a triple into the oracle Agent node's knowledge_graph JSON column.
   *
   * D-007: all triple writes route through this verb — no raw Cypher in callers.
   * Idempotent: if an identical (subject, predicate, object) triple already exists,
   * it is NOT duplicated.
   *
   * @param agentFp   Blake3 fp of the oracle Agent node
   * @param subject   Subject fp (hex string)
   * @param predicate Predicate string (e.g. "lives-in")
   * @param object    Object fp (hex string)
   */
  insertTriple(agentFp: string, subject: string, predicate: string, object: string): Promise<void>;

  /**
   * Delete a triple from the oracle Agent node's knowledge_graph JSON column.
   *
   * D-007: all triple deletes route through this verb.
   * No-op if the triple does not exist.
   *
   * @param agentFp   Blake3 fp of the oracle Agent node
   * @param subject   Subject fp (hex string)
   * @param predicate Predicate string
   * @param object    Object fp (hex string)
   */
  deleteTriple(agentFp: string, subject: string, predicate: string, object: string): Promise<void>;

  /**
   * Update a triple in the oracle Agent node's knowledge_graph: replace the old triple
   * with the new triple atomically.
   *
   * D-007: all triple updates route through this verb.
   * Equivalent to deleteTriple(old) + insertTriple(new) but as a single read-modify-write.
   *
   * @param agentFp      Blake3 fp of the oracle Agent node
   * @param subject      Subject fp of the triple to replace
   * @param predicate    Predicate of the triple to replace
   * @param oldObject    Old object fp
   * @param newObject    New object fp
   */
  updateTriple(
    agentFp: string,
    subject: string,
    predicate: string,
    oldObject: string,
    newObject: string
  ): Promise<void>;

  /**
   * Return all triples from the oracle Agent's knowledge_graph where subject = fp.
   *
   * Used by S4.3 tests to verify mirror correctness.
   *
   * @param agentFp  Blake3 fp of the oracle Agent node
   * @param fp       Subject fp to filter on (or '*' for all triples)
   */
  triplesFor(agentFp: string, fp: string): Promise<Array<{ subject: string; predicate: string; object: string }>>;

  /**
   * Return ActionLog rows for a palace whose fp is lexicographically greater than
   * sinceActionFp (i.e. actions added after the given cursor). Returns all actions
   * when sinceActionFp is '' (empty string cursor).
   *
   * Used by S4.3 AC6 interleaved-reader test.
   *
   * @param palaceFp Blake3 fp of the palace
   * @param opts     Optional cursor: afterTimestamp (ms epoch, exclusive). Omit or 0 for all.
   */
  actionsSince(palaceFp: string, opts?: { afterTimestamp?: number }): Promise<Array<{ fp: string; actionKind: string; targetFp: string; timestamp: number }>>;

  // ── S4.4 file-watcher domain verbs ───────────────────────────────────────

  /**
   * Update an Inscription node's mutable fields after a file-watcher edit.
   *
   * Sets source_blake3 (new content hash) and bumps revision by 1.
   * Used by file-watcher.ts as part of the 4-step inline-sync transaction.
   *
   * D-007: domain verb — no raw Cypher in file-watcher.ts.
   *
   * @param avatarFp    Blake3 fp of the inscription to update
   * @param fields      Fields to update (source_blake3 and/or revision)
   */
  updateInscription(avatarFp: string, fields: { source_blake3?: string; revision?: number }): Promise<void>;

  /**
   * Set Inscription.orphaned = true for the given avatar fp.
   *
   * Used by file-watcher.ts when the source file is deleted from disk (AC3).
   * Does NOT remove the embedding vector or LIVES_IN edge (quarantine semantics).
   *
   * D-007: domain verb — no raw Cypher in file-watcher.ts.
   *
   * @param avatarFp  Blake3 fp of the inscription to mark orphaned
   */
  markOrphaned(avatarFp: string): Promise<void>;

  // ── Policy-gated read verbs (S4.2) ───────────────────────────────────────

  /**
   * Fetch an inscription's data, subject to Guild policy gate.
   *
   * requesterFp is REQUIRED (no anonymous default — OQ-S4.2-a recommendation).
   *
   * Policy path:
   *   - If requester is oracle fp → allow (oracle-bypass, SEC5).
   *   - If requester is Guild member → allow (guild-member, SEC4).
   *   - Otherwise → deny, throws PolicyDeniedError.
   *
   * Audit log records one entry per call with the resolved reason.
   *
   * @param avatarFp    Blake3 fp of the inscription (avatar)
   * @param requesterFp Blake3 fp of the agent requesting the read (REQUIRED)
   */
  getInscription(avatarFp: string, requesterFp: string): Promise<InscriptionData | null>;

  /**
   * Return the full mythos chain as triples for a palace.
   *
   * AC6 / SEC3: always returns the full chain regardless of Guild policy.
   * Audit log records reason: 'mythos-always-public'.
   *
   * requesterFp is REQUIRED for audit trail completeness.
   *
   * @param palaceFp    Blake3 fp of the palace
   * @param requesterFp Blake3 fp of the requester (any value — always allowed)
   */
  mythosChainTriples(palaceFp: string, requesterFp: string): Promise<MythosTriple[]>;

  // ── Inscription body read (S5.4 — InscriptionLens consumer, D-007, TC13) ──

  /**
   * Fetch CAS body bytes for an inscription (D-007 / TC13 / AC3).
   *
   * Flow:
   *   1. Queries `source_blake3` for the inscription fp from the store.
   *   2. Reads raw bytes from CAS (server: filesystem; browser: same-origin /cas/:hash).
   *   3. Hash-verifies: asserts Blake3(bytes) === source_blake3.
   *   4. Returns the verified Uint8Array.
   *
   * SEC6: MUST NOT fetch from non-local URLs. No raw filesystem path constructed
   * by the caller — all path logic lives inside the store implementation.
   *
   * Throws if the inscription is not found, if CAS bytes are unavailable, or if
   * hash verification fails.
   *
   * @param inscriptionFp  Blake3 fp of the inscription avatar
   */
  inscriptionBody(inscriptionFp: string): Promise<Uint8Array>;

  /**
   * Return public InscriptionLens dispatch metadata (surface + fallback chain)
   * for an inscription fp. Non-gated — these are display attributes, not sensitive.
   *
   * Returns null if the inscription fp is not found.
   * When the inscription has no `surface` attribute, the returned `surface` is
   * 'scroll' (ADR 2026-04-24-surface-registry — scroll is the canonical baseline).
   * When no `fallback` attribute is stored, returns `[]` (absent ≡ empty per ADR §4).
   */
  inscriptionMeta(inscriptionFp: string): Promise<InscriptionMeta | null>;

  // ── Palace / Room read verbs (S5.2 — PalaceLens consumer) ───────────────

  /**
   * Return summary data for a palace (field envelope).
   *
   * D-007: the sole entry point for palace-level reads from lens code.
   * Returns null if the palace fp is not found in the store.
   *
   * @param palaceFp  Blake3 fp of the palace (jelly.dreamball.field)
   */
  getPalace(palaceFp: string): Promise<PalaceData | null>;

  /**
   * Return all rooms contained within a palace.
   *
   * D-007: returns decoded room data including jelly.layout when present
   * (or null when absent — triggers AC3 grid-fallback in the lens).
   * Order is deterministic: rooms are returned sorted by fp lexicographically,
   * which gives the grid-fallback stable positions across mounts.
   *
   * @param palaceFp  Blake3 fp of the palace
   */
  roomsFor(palaceFp: string): Promise<RoomData[]>;

  /**
   * Return all inscriptions contained within a room, with placement data.
   *
   * D-007: the sole entry point for room-interior reads from RoomLens (S5.3 / FR16).
   * Each item carries a `placement` object when jelly.layout specifies position +
   * facing for that inscription; null when absent → lens uses deterministic grid
   * fallback. Items are returned sorted by fp lexicographically for stable grid
   * fallback ordering across mounts.
   *
   * @param roomFp  Blake3 fp of the room
   */
  roomContents(roomFp: string): Promise<RoomContentsItem[]>;

  // ── Diagnostic escape hatch ───────────────────────────────────────────────

  /**
   * Execute an arbitrary Cypher query.
   *
   * @deprecated-for-new-callers diagnostic-only
   *
   * This is the ONLY function in StoreAPI whose name matches /raw|cypher/i.
   * It exists for oracle diagnostics and tests. Do NOT call from Epic C/D/E/F
   * production code — add a named verb instead.
   */
  __rawQuery<T = Record<string, unknown>>(cypher: string): Promise<T[]>;

  // ── Write-context + oracle registry (S4.2 SEC5) ──────────────────────────

  /**
   * Set the active write context for subsequent mutation verbs. Returns a
   * restore() closure that resets the context to its prior value. Every
   * mutation verb consults this via evaluateWritePolicy before issuing Cypher.
   * Default context is { requesterFp: '', origin: 'custodian' } — which always
   * allows (matches pre-S4.2 behaviour for callers that don't opt in).
   */
  setWriteContext(ctx: WriteContext): () => void;

  /** Register an oracle fp for a palace (S4.2) — declared here so TS callers see it on the interface. */
  registerOracleFp(palaceFp: string, oracleFp: string): void;
}

// ── Policy errors ─────────────────────────────────────────────────────────────

/** Thrown by getInscription when Guild policy denies access. */
export class PolicyDeniedError extends Error {
  constructor(public readonly reason: string, public readonly avatarFp: string) {
    super(`Policy denied access to inscription '${avatarFp}': ${reason}`);
    this.name = 'PolicyDeniedError';
  }
}

// ── Sentinel error thrown by unimplemented vector verbs ───────────────────────

export class NotImplementedInS22 extends Error {
  constructor(verb: string) {
    super(
      `${verb} is not implemented in S2.2 — TODO-EMBEDDING: implement in S2.5`
    );
    this.name = 'NotImplementedInS22';
  }
}

// ── Sentinel error thrown when open() is called on an already-open store ──────

/**
 * Thrown by BrowserStore.open() if called a second time when the store is
 * already open and the implementation opts for the "throw" variant of AC10.
 *
 * The current implementation uses the "return existing handle" variant (AC10
 * preferred), so this class is exported for callers that want to distinguish
 * the error type in future implementations or tests.
 */
export class StoreAlreadyOpen extends Error {
  constructor() {
    super('Store is already open — call close() before calling open() again');
    this.name = 'StoreAlreadyOpen';
  }
}
