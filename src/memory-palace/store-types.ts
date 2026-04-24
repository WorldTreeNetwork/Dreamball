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
   * @param palaceFp      Blake3 fp of the palace
   * @param sinceActionFp Cursor fp (exclusive lower bound, or '' for all)
   */
  actionsSince(palaceFp: string, sinceActionFp: string): Promise<Array<{ fp: string; actionKind: string; targetFp: string }>>;

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
