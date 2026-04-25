/**
 * store.server.ts — Server-side StoreAPI implementation using @ladybugdb/core napi.
 *
 * TC12: This file is the ONLY place that imports @ladybugdb/core.
 *       grep -R "@ladybugdb/core" src/ jelly-server/ (excluding store*.ts) must return zero.
 *
 * TC9:  Every conn.query() is wrapped in runQuery() which calls qr.close() in a finally block.
 *       No QueryResult handle leaks.
 *
 * TC13: No CBOR bytes stored. Every reference is a Blake3 hex string.
 *
 * D-007: Domain verbs only in the public surface. __rawQuery is the sole escape hatch.
 *
 * D-016: Schema per src/memory-palace/schema.cypher (S2.4). DDL executed on open().
 *
 * SEC5 / S4.2 AC5: every mutation verb consults `_gateWrite(verb)` which
 * delegates to `evaluateWritePolicy`. The default write context has an empty
 * `requesterFp`, which bypasses the gate — that path is reserved for
 * custodian-authenticated callers whose identity is proven upstream by Zig.
 *
 * Cypher-interpolation hardening: every dynamic value routes through a
 * validator in cypher-utils.ts. No local esc()/escArr() helpers remain.
 * See cypher-utils.ts for the rationale; this file is the primary consumer.
 *
 * VECTOR extension: @ladybugdb/core 0.15.3 bundles the VECTOR extension but does NOT
 * auto-load it. open() calls INSTALL VECTOR + LOAD EXTENSION VECTOR before DDL,
 * then issues CREATE_VECTOR_INDEX guarded by SHOW_INDEXES(). (Discovered in S2.1 spike.)
 *
 * NFR18 replay: recordAction + mirrorAction (action-mirror.ts) are the dual-write path.
 */

import lbug from '@ladybugdb/core';
import type { LbugValue } from '@ladybugdb/core';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';
import {
  type StoreAPI,
  type RecordActionParams,
  type InscriptionData,
  type MythosTriple,
  type WriteContext,
  type PalaceData,
  type RoomData,
  PolicyDeniedError,
} from './store-types.js';
import { mirrorAction, type MirrorAction } from './action-mirror.js';
import {
  evaluateGuildPolicy,
  evaluateMythosPolicy,
  evaluateWritePolicy,
  defaultAuditLog,
  type PolicySlot,
} from './policy.js';
import {
  updateStrength,
  computeConductance,
  DEFAULT_ALPHA,
  DEFAULT_TAU_MS,
} from './aqueduct.js';
import {
  sanitizeFp,
  sanitizeOptionalFp,
  sanitizeFpArray,
  sanitizeActionKind,
  sanitizePolicy,
  sanitizeCanonicality,
  sanitizeInt,
  sanitizeFloat,
  cypherString,
  cypherFpArray,
  deriveAqueductFp,
  deriveTripleFp,
  hashBytesBlake3Hex,
} from './cypher-utils.js';

// ── Internal query wrapper (TC9) ──────────────────────────────────────────────

/**
 * Execute a Cypher string and return all rows, closing the QueryResult
 * handle before returning (TC9). If conn.query() returns an array of
 * QueryResult (multi-statement), only the last result's rows are returned.
 */
async function runQuery<T = Record<string, LbugValue>>(
  conn: InstanceType<typeof lbug.Connection>,
  cypher: string
): Promise<T[]> {
  const raw = await conn.query(cypher);
  const qr = Array.isArray(raw) ? raw[raw.length - 1] : raw;
  try {
    return (await qr.getAll()) as T[];
  } finally {
    qr.close();
  }
}

// ── DDL ───────────────────────────────────────────────────────────────────────

/**
 * Load schema.cypher and execute each CREATE statement idempotently.
 *
 * AC3: Tables that already exist (per SHOW_TABLES) are skipped — no
 * duplicate-table error on second open().
 *
 * AC4: After node/rel DDL, CREATE_VECTOR_INDEX is issued if not already
 * present (per SHOW_INDEXES).
 *
 * schema.cypher uses SQL-style `--` line comments which we strip before
 * splitting on `;`.
 */
async function runDDL(conn: InstanceType<typeof lbug.Connection>): Promise<void> {
  // Load schema.cypher relative to this file
  const schemaPath = join(dirname(fileURLToPath(import.meta.url)), 'schema.cypher');
  const raw = readFileSync(schemaPath, 'utf-8');

  // Strip line comments and split on semicolons
  const statements = raw
    .split('\n')
    .filter((line) => !line.trimStart().startsWith('--'))
    .join('\n')
    .split(';')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

  // Discover existing tables
  const tables = await runQuery<{ name: string }>(conn, 'CALL SHOW_TABLES() RETURN *');
  const existing = new Set(tables.map((r) => String(r.name)));

  for (const stmt of statements) {
    // Extract table name from CREATE NODE TABLE / CREATE REL TABLE
    const nodeMatch = stmt.match(/CREATE\s+NODE\s+TABLE\s+(\w+)/i);
    const relMatch = stmt.match(/CREATE\s+REL\s+TABLE\s+(\w+)/i);
    const tableName = nodeMatch?.[1] ?? relMatch?.[1];

    if (tableName && existing.has(tableName)) {
      continue; // already exists — skip
    }

    await runQuery(conn, stmt);
  }

  // AC4: Vector index — guarded by SHOW_INDEXES()
  await ensureVectorIndex(conn);
}

async function ensureVectorIndex(conn: InstanceType<typeof lbug.Connection>): Promise<void> {
  const indexes = await runQuery<{ index_name: string }>(conn, 'CALL SHOW_INDEXES() RETURN *');
  const hasIndex = indexes.some((r) => String(r.index_name) === 'inscription_emb');
  if (!hasIndex) {
    await runQuery(
      conn,
      `CALL CREATE_VECTOR_INDEX('Inscription', 'inscription_emb', 'embedding')`
    );
  }
}

// ── ServerStore ───────────────────────────────────────────────────────────────

export class ServerStore implements StoreAPI {
  private db: InstanceType<typeof lbug.Database> | null = null;
  private conn: InstanceType<typeof lbug.Connection> | null = null;
  private dbPath: string;
  /**
   * CAS directory for inscription body bytes (S5.4 / AC3 / TC13).
   * Each file is named by its Blake3 hex hash (64 lowercase hex chars).
   * Default: ':none:' — means CAS reads are not available on this store instance.
   * Set via constructor `opts.casDir` or the PALACE_CAS_DIR env var.
   */
  private _casDir: string;

  /**
   * Per-palace oracle fp registry (S4.2).
   * Populated by registerOracleFp(palaceFp, oracleFp) — called at palace open/mint.
   * Used by getInscription and mythosChainTriples to resolve the oracle fp for
   * evaluateGuildPolicy / isOracleRequester.
   */
  private _oracleFpByPalace: Map<string, string> = new Map();

  /** Reverse index of oracle fps known to this store (for write-gate membership). */
  private _knownOracleFps: Set<string> = new Set();

  /** Active write-context for the next mutation verb. */
  private _writeCtx: WriteContext = { requesterFp: '', origin: 'custodian' };

  constructor(dbPath = ':memory:', opts: { casDir?: string } = {}) {
    this.dbPath = dbPath;
    this._casDir = opts.casDir ?? (process.env['PALACE_CAS_DIR'] ?? ':none:');
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  async open(): Promise<void> {
    if (this.conn !== null) return; // idempotent

    this.db = new lbug.Database(this.dbPath);
    this.conn = new lbug.Connection(this.db);

    // VECTOR extension must be explicitly loaded (not auto-loaded in v0.15.3).
    // Discovered during S2.1 spike — see Dev Agent Record.
    await runQuery(this.conn, 'INSTALL VECTOR');
    await runQuery(this.conn, 'LOAD EXTENSION VECTOR');

    await runDDL(this.conn);
  }

  async close(): Promise<void> {
    if (this.conn === null) return;
    await this.conn.close();
    await this.db!.close();
    this.conn = null;
    this.db = null;
  }

  /** AC7: no-op on server — resolves within 1 ms */
  async syncfs(_direction: 'in' | 'out'): Promise<void> {
    // Server has no IDBFS. Intentional no-op.
    return;
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  private get _conn(): InstanceType<typeof lbug.Connection> {
    if (!this.conn) throw new Error('Store not open — call open() first');
    return this.conn;
  }

  private async _q<T = Record<string, LbugValue>>(cypher: string): Promise<T[]> {
    return runQuery<T>(this._conn, cypher);
  }

  /**
   * SEC5 / S4.2 AC5 write-gate.
   *
   * Every mutation verb begins with `this._gateWrite('<verbName>')`. If the
   * active write context is anonymous (requesterFp === '') the gate is a
   * no-op — that path belongs to custodian-signed callers whose identity was
   * proven upstream by Zig. If requesterFp matches a known oracle fp we delegate
   * to `evaluateWritePolicy` which allows only the file-watcher origin.
   *
   * Throws `PolicyDeniedError` on denial; the verb never runs Cypher.
   */
  private _gateWrite(verb: string): void {
    const { requesterFp, origin } = this._writeCtx;
    // Default/anonymous writes pass through (custodian-signed path is authenticated upstream by Zig).
    if (!requesterFp) return;
    // Only oracle-identified writes are subject to the SEC5 file-watcher gate.
    if (!this._knownOracleFps.has(requesterFp)) return;
    // Find any palace fp that maps to this oracle (for audit context).
    let palaceFp = '';
    for (const [pFp, oFp] of this._oracleFpByPalace) {
      if (oFp === requesterFp) {
        palaceFp = pFp;
        break;
      }
    }
    const decision = evaluateWritePolicy(verb, requesterFp, palaceFp, {
      oracleFp: requesterFp,
      auditLog: defaultAuditLog,
      ctx: { origin },
    });
    if (!decision.allow) {
      throw new PolicyDeniedError(decision.reason, verb);
    }
  }

  // ── Containment verbs ───────────────────────────────────────────────────────

  async ensurePalace(
    fp: string,
    _mythosHeadFp?: string,
    _opts?: { formatVersion?: number; revision?: number }
  ): Promise<void> {
    this._gateWrite('ensurePalace');
    const pFp = sanitizeFp(fp, 'palaceFp');
    const now = Date.now();
    const existing = await this._q<{ fp: string }>(
      `MATCH (p:Palace {fp: '${pFp}'}) RETURN p.fp AS fp`
    );
    if (existing.length === 0) {
      await this._q(
        `CREATE (:Palace {
          fp: '${pFp}',
          created_at: ${now},
          mythos_head_fp: ''
        })`
      );
    }
  }

  async addRoom(
    palaceFp: string,
    roomFp: string,
    _opts?: { name?: string; archiform?: string }
  ): Promise<void> {
    this._gateWrite('addRoom');
    const pFp = sanitizeFp(palaceFp, 'palaceFp');
    const rFp = sanitizeFp(roomFp, 'roomFp');
    const now = Date.now();
    const existing = await this._q<{ fp: string }>(
      `MATCH (r:Room {fp: '${rFp}'}) RETURN r.fp AS fp`
    );
    if (existing.length === 0) {
      await this._q(
        `CREATE (:Room {
          fp: '${rFp}',
          created_at: ${now}
        })`
      );
    }
    const edgeExists = await this._q<Record<string, unknown>>(
      `MATCH (p:Palace {fp: '${pFp}'})-[e:CONTAINS]->(r:Room {fp: '${rFp}'})
       RETURN e`
    );
    if (edgeExists.length === 0) {
      await this._q(
        `MATCH (p:Palace {fp: '${pFp}'})
         MATCH (r:Room {fp: '${rFp}'})
         CREATE (p)-[:CONTAINS]->(r)`
      );
    }
  }

  async inscribeAvatar(
    roomFp: string,
    avatarFp: string,
    sourceBlake3: string,
    _opts?: { surface?: string; embedding?: Float32Array | null; archiform?: string }
  ): Promise<void> {
    this._gateWrite('inscribeAvatar');
    const rFp = sanitizeFp(roomFp, 'roomFp');
    const aFp = sanitizeFp(avatarFp, 'avatarFp');
    const sb = sanitizeFp(sourceBlake3, 'sourceBlake3');
    const now = Date.now();
    const existing = await this._q<{ fp: string }>(
      `MATCH (i:Inscription {fp: '${aFp}'}) RETURN i.fp AS fp`
    );
    if (existing.length === 0) {
      await this._q(
        `CREATE (:Inscription {
          fp: '${aFp}',
          source_blake3: '${sb}',
          orphaned: false,
          created_at: ${now},
          policy: 'public',
          revision: 0
        })`
      );
    }
    const containsExists = await this._q<Record<string, unknown>>(
      `MATCH (r:Room {fp: '${rFp}'})-[e:CONTAINS]->(i:Inscription {fp: '${aFp}'})
       RETURN e`
    );
    if (containsExists.length === 0) {
      await this._q(
        `MATCH (r:Room {fp: '${rFp}'})
         MATCH (i:Inscription {fp: '${aFp}'})
         CREATE (r)-[:CONTAINS]->(i)`
      );
    }
    const livesExists = await this._q<Record<string, unknown>>(
      `MATCH (i:Inscription {fp: '${aFp}'})-[e:LIVES_IN]->(r:Room {fp: '${rFp}'})
       RETURN e`
    );
    if (livesExists.length === 0) {
      await this._q(
        `MATCH (i:Inscription {fp: '${aFp}'})
         MATCH (r:Room {fp: '${rFp}'})
         CREATE (i)-[:LIVES_IN]->(r)`
      );
    }
  }

  // ── Mythos-chain verbs ──────────────────────────────────────────────────────

  async setMythosHead(
    palaceFp: string,
    mythosFp: string,
    opts?: { actionFp?: string; isGenesis?: boolean; bodyHash?: string }
  ): Promise<void> {
    this._gateWrite('setMythosHead');
    const pFp = sanitizeFp(palaceFp, 'palaceFp');
    const mFp = sanitizeFp(mythosFp, 'mythosFp');
    const actionFp = sanitizeOptionalFp(opts?.actionFp ?? '', 'actionFp');
    const canonicality = sanitizeCanonicality(opts?.isGenesis ? 'genesis' : 'successor');
    const now = Date.now();
    const mExists = await this._q<{ fp: string }>(
      `MATCH (m:Mythos {fp: '${mFp}'}) RETURN m.fp AS fp`
    );
    if (mExists.length === 0) {
      await this._q(
        `CREATE (:Mythos {
          fp: '${mFp}',
          body: '',
          canonicality: '${canonicality}',
          discovered_in_action_fp: '${actionFp}',
          created_at: ${now}
        })`
      );
    }
    const headExists = await this._q<Record<string, unknown>>(
      `MATCH (p:Palace {fp: '${pFp}'})-[e:MYTHOS_HEAD]->(:Mythos)
       RETURN e`
    );
    if (headExists.length > 0) {
      await this._q(
        `MATCH (p:Palace {fp: '${pFp}'})-[e:MYTHOS_HEAD]->(:Mythos)
         DELETE e`
      );
    }
    await this._q(
      `MATCH (p:Palace {fp: '${pFp}'})
       MATCH (m:Mythos {fp: '${mFp}'})
       CREATE (p)-[:MYTHOS_HEAD]->(m)`
    );
    await this._q(
      `MATCH (p:Palace {fp: '${pFp}'})
       SET p.mythos_head_fp = '${mFp}'`
    );
  }

  async appendMythos(
    newFp: string,
    predecessorFp: string,
    opts?: { bodyHash?: string; trueName?: string; discoveredInActionFp?: string }
  ): Promise<void> {
    this._gateWrite('appendMythos');
    const nFp = sanitizeFp(newFp, 'newFp');
    const pFp = sanitizeFp(predecessorFp, 'predecessorFp');
    const discoveredIn = sanitizeOptionalFp(opts?.discoveredInActionFp ?? '', 'discoveredInActionFp');
    const now = Date.now();
    const nExists = await this._q<{ fp: string }>(
      `MATCH (m:Mythos {fp: '${nFp}'}) RETURN m.fp AS fp`
    );
    if (nExists.length === 0) {
      await this._q(
        `CREATE (:Mythos {
          fp: '${nFp}',
          body: '',
          canonicality: 'successor',
          discovered_in_action_fp: '${discoveredIn}',
          created_at: ${now}
        })`
      );
    }
    const predExists = await this._q<Record<string, unknown>>(
      `MATCH (n:Mythos {fp: '${nFp}'})-[e:PREDECESSOR]->(p:Mythos {fp: '${pFp}'})
       RETURN e`
    );
    if (predExists.length === 0) {
      await this._q(
        `MATCH (n:Mythos {fp: '${nFp}'})
         MATCH (p:Mythos {fp: '${pFp}'})
         CREATE (n)-[:PREDECESSOR]->(p)`
      );
    }
  }

  async getMythosHead(palaceFp: string): Promise<string | null> {
    const pFp = sanitizeFp(palaceFp, 'palaceFp');
    const rows = await this._q<{ fp: string }>(
      `MATCH (p:Palace {fp: '${pFp}'})-[:MYTHOS_HEAD]->(m:Mythos)
       RETURN m.fp AS fp`
    );
    return rows.length > 0 ? String(rows[0].fp) : null;
  }

  // ── Action log ──────────────────────────────────────────────────────────────

  async recordAction(params: RecordActionParams): Promise<void> {
    this._gateWrite('recordAction');
    const fp = sanitizeFp(params.fp, 'fp');
    const pFp = sanitizeFp(params.palaceFp, 'palaceFp');
    const actionKind = sanitizeActionKind(params.actionKind);
    const actorFp = sanitizeFp(params.actorFp, 'actorFp');
    const tFp = sanitizeOptionalFp(params.targetFp ?? '', 'targetFp');
    const parentHashes = sanitizeFpArray(params.parentHashes, 'parentHashes');
    // schema.cypher uses INT64 for timestamp (ms epoch) — not TIMESTAMP()
    const tsIn = params.timestamp;
    const ts =
      tsIn instanceof Date
        ? tsIn.getTime()
        : typeof tsIn === 'number'
          ? tsIn
          : new Date(tsIn).getTime();
    const tsInt = sanitizeInt(ts, 'timestamp');
    const cbor = sanitizeOptionalFp(params.cborBytesBlake3 ?? '', 'cborBytesBlake3');
    await this._q(
      `CREATE (:ActionLog {
        fp: '${fp}',
        palace_fp: '${pFp}',
        action_kind: '${actionKind}',
        actor_fp: '${actorFp}',
        target_fp: '${tFp}',
        parent_hashes: ${cypherFpArray(parentHashes)},
        timestamp: ${tsInt},
        cbor_bytes_blake3: '${cbor}'
      })`
    );
  }

  /**
   * Return tip hashes: fps in ActionLog for palaceFp that do NOT appear
   * in any other row's parent_hashes for that same palace.
   */
  async headHashes(palaceFp: string): Promise<string[]> {
    const pFp = sanitizeFp(palaceFp, 'palaceFp');
    const rows = await this._q<{ fp: string; parent_hashes: LbugValue }>(
      `MATCH (a:ActionLog {palace_fp: '${pFp}'})
       RETURN a.fp AS fp, a.parent_hashes AS parent_hashes`
    );
    const allFps = new Set(rows.map((r) => String(r.fp)));
    const referenced = new Set<string>();
    for (const row of rows) {
      const ph = row.parent_hashes;
      if (Array.isArray(ph)) {
        for (const p of ph) {
          if (p !== null && p !== undefined) referenced.add(String(p));
        }
      }
    }
    return [...allFps].filter((fp) => !referenced.has(fp));
  }

  // ── Vector verbs (S2.5 — FR21 sole vector-write path) ───────────────────────

  /**
   * Upsert an embedding vector on an Inscription node.
   *
   * LadybugDB/kuzu constraint: SET on a vector column that participates in a
   * VECTOR INDEX raises "Cannot set prop ... because it is used in one or more
   * indexes." The correct pattern is to read ALL non-embedding row properties
   * (including policy + revision — see schema.cypher), delete the node, and
   * re-create it with the new embedding.
   *
   * Crucially the pre-delete read MUST include `policy` and `revision` so the
   * file-watcher's revision bumps and any guild policy tightening survive the
   * round-trip. Dropping those columns silently reset revisions to 0 — a
   * replay-correctness regression fixed by the CRITICAL review pass.
   */
  async upsertEmbedding(fp: string, vec: Float32Array): Promise<void> {
    this._gateWrite('upsertEmbedding');
    const iFp = sanitizeFp(fp, 'fp');
    const rows = await this._q<{
      source_blake3: string;
      orphaned: boolean;
      created_at: number;
      policy: string;
      revision: number;
    }>(
      `MATCH (i:Inscription {fp: '${iFp}'})
       RETURN i.source_blake3 AS source_blake3, i.orphaned AS orphaned,
              i.created_at AS created_at, i.policy AS policy, i.revision AS revision`
    );
    if (rows.length === 0) return;

    const row = rows[0];
    const containsEdges = await this._q<{ room_fp: string }>(
      `MATCH (r:Room)-[:CONTAINS]->(i:Inscription {fp: '${iFp}'}) RETURN r.fp AS room_fp`
    );
    const livesInEdges = await this._q<{ room_fp: string }>(
      `MATCH (i:Inscription {fp: '${iFp}'})-[:LIVES_IN]->(r:Room) RETURN r.fp AS room_fp`
    );

    await this._q(`MATCH (i:Inscription {fp: '${iFp}'}) DETACH DELETE i`);

    const arr = `[${Array.from(vec).map((f) => sanitizeFloat(f, 'embedding')).join(',')}]`;
    const policy = sanitizePolicy(row.policy ?? 'public');
    const revision = sanitizeInt(row.revision ?? 0, 'revision');
    const sb = sanitizeFp(String(row.source_blake3), 'source_blake3');
    const createdAt = sanitizeInt(row.created_at, 'created_at');
    await this._q(
      `CREATE (:Inscription {
        fp: '${iFp}',
        source_blake3: '${sb}',
        orphaned: ${Boolean(row.orphaned)},
        embedding: CAST(${arr} AS FLOAT[256]),
        created_at: ${createdAt},
        policy: ${cypherString(policy)},
        revision: ${revision}
      })`
    );

    for (const { room_fp } of containsEdges) {
      const roomFp = sanitizeFp(String(room_fp), 'roomFp');
      await this._q(
        `MATCH (r:Room {fp: '${roomFp}'})
         MATCH (i:Inscription {fp: '${iFp}'})
         CREATE (r)-[:CONTAINS]->(i)`
      );
    }
    for (const { room_fp } of livesInEdges) {
      const roomFp = sanitizeFp(String(room_fp), 'roomFp');
      await this._q(
        `MATCH (i:Inscription {fp: '${iFp}'})
         MATCH (r:Room {fp: '${roomFp}'})
         CREATE (i)-[:LIVES_IN]->(r)`
      );
    }
  }

  /**
   * Clear the embedding on an Inscription by delete + recreate (without the
   * embedding column). Preserves policy + revision just like upsertEmbedding.
   */
  async deleteEmbedding(fp: string): Promise<void> {
    this._gateWrite('deleteEmbedding');
    const iFp = sanitizeFp(fp, 'fp');
    const rows = await this._q<{
      source_blake3: string;
      orphaned: boolean;
      created_at: number;
      policy: string;
      revision: number;
    }>(
      `MATCH (i:Inscription {fp: '${iFp}'})
       RETURN i.source_blake3 AS source_blake3, i.orphaned AS orphaned,
              i.created_at AS created_at, i.policy AS policy, i.revision AS revision`
    );
    if (rows.length === 0) return;

    const row = rows[0];
    const containsEdges = await this._q<{ room_fp: string }>(
      `MATCH (r:Room)-[:CONTAINS]->(i:Inscription {fp: '${iFp}'}) RETURN r.fp AS room_fp`
    );
    const livesInEdges = await this._q<{ room_fp: string }>(
      `MATCH (i:Inscription {fp: '${iFp}'})-[:LIVES_IN]->(r:Room) RETURN r.fp AS room_fp`
    );

    await this._q(`MATCH (i:Inscription {fp: '${iFp}'}) DETACH DELETE i`);

    const policy = sanitizePolicy(row.policy ?? 'public');
    const revision = sanitizeInt(row.revision ?? 0, 'revision');
    const sb = sanitizeFp(String(row.source_blake3), 'source_blake3');
    const createdAt = sanitizeInt(row.created_at, 'created_at');
    await this._q(
      `CREATE (:Inscription {
        fp: '${iFp}',
        source_blake3: '${sb}',
        orphaned: ${Boolean(row.orphaned)},
        created_at: ${createdAt},
        policy: ${cypherString(policy)},
        revision: ${revision}
      })`
    );

    for (const { room_fp } of containsEdges) {
      const roomFp = sanitizeFp(String(room_fp), 'roomFp');
      await this._q(
        `MATCH (r:Room {fp: '${roomFp}'})
         MATCH (i:Inscription {fp: '${iFp}'})
         CREATE (r)-[:CONTAINS]->(i)`
      );
    }
    for (const { room_fp } of livesInEdges) {
      const roomFp = sanitizeFp(String(room_fp), 'roomFp');
      await this._q(
        `MATCH (i:Inscription {fp: '${iFp}'})
         MATCH (r:Room {fp: '${roomFp}'})
         CREATE (i)-[:LIVES_IN]->(r)`
      );
    }
  }

  /**
   * FR21 delete-then-insert vector write — the SOLE vector-write code path.
   *
   * Short-circuits when the new bytes hash matches the stored source_blake3
   * (AC9). Otherwise runs deleteEmbedding → upsertEmbedding → source_blake3 SET.
   */
  async reembed(fp: string, newBytes: Uint8Array, newVec: Float32Array): Promise<void> {
    this._gateWrite('reembed');
    const iFp = sanitizeFp(fp, 'fp');
    const rows = await this._q<{ source_blake3: string }>(
      `MATCH (i:Inscription {fp: '${iFp}'}) RETURN i.source_blake3 AS source_blake3`
    );
    const currentHash = rows.length > 0 ? String(rows[0].source_blake3) : '';

    const newHash = await hashBytesBlake3Hex(newBytes);

    if (newHash === currentHash) {
      return;
    }

    await this.deleteEmbedding(iFp);
    await this.upsertEmbedding(iFp, newVec);

    const validated = sanitizeFp(newHash, 'newHash');
    await this._q(
      `MATCH (i:Inscription {fp: '${iFp}'})
       SET i.source_blake3 = '${validated}'`
    );
  }

  /**
   * K-nearest-neighbour query over Inscription.embedding (server side).
   *
   * D-016 Cypher pattern: QUERY_VECTOR_INDEX → YIELD node AS i, distance →
   * MATCH (i:Inscription)-[:LIVES_IN]->(r:Room) → RETURN fp, roomFp, distance
   * ORDER BY distance ASC. (AC2)
   */
  async kNN(
    vec: Float32Array,
    k: number,
    _filter?: { palaceFp?: string; roomFp?: string }
  ): Promise<Array<{ fp: string; roomFp: string; distance: number }>> {
    const kInt = sanitizeInt(k, 'k');
    const arr = `[${Array.from(vec).map((f) => sanitizeFloat(f, 'embedding')).join(',')}]`;
    const results = await this._q<{ fp: string; roomFp: string; distance: number }>(
      `CALL QUERY_VECTOR_INDEX('Inscription', 'inscription_emb', CAST(${arr} AS FLOAT[256]), ${kInt})
       YIELD node AS i, distance
       MATCH (i:Inscription)-[:LIVES_IN]->(r:Room)
       RETURN i.fp AS fp, r.fp AS roomFp, distance
       ORDER BY distance ASC`
    );
    return results.map((r) => ({ fp: String(r.fp), roomFp: String(r.roomFp), distance: Number(r.distance) }));
  }

  // ── Aqueduct helpers ─────────────────────────────────────────────────────────

  /**
   * Lazily create an Aqueduct between two rooms if none exists (D-003).
   * Aqueduct fp is derived deterministically from (roomA, roomB, palace) via
   * deriveAqueductFp — replay from ActionLog therefore reproduces the same fp.
   * The aqueduct-created ActionLog row fp is a derived blake3 of the aqueduct
   * fp plus the literal "aqueduct-created" predicate (no timestamps in fps).
   */
  async getOrCreateAqueduct(
    fromRoomFp: string,
    toRoomFp: string,
    palaceFp: string
  ): Promise<string> {
    this._gateWrite('getOrCreateAqueduct');
    const fromFp = sanitizeFp(fromRoomFp, 'fromRoomFp');
    const toFp = sanitizeFp(toRoomFp, 'toRoomFp');
    const pFp = sanitizeFp(palaceFp, 'palaceFp');

    const existing = await this._q<{ fp: string }>(
      `MATCH (a:Aqueduct)-[:AQUEDUCT_FROM]->(r1:Room {fp: '${fromFp}'})
       MATCH (a)-[:AQUEDUCT_TO]->(r2:Room {fp: '${toFp}'})
       RETURN a.fp AS fp`
    );
    if (existing.length > 0) {
      return String(existing[0].fp);
    }

    const aqFp = await deriveAqueductFp(fromFp, toFp, pFp);
    const ts = Date.now();

    await this._q(
      `CREATE (:Aqueduct {
        fp: '${aqFp}',
        from_fp: '${fromFp}',
        to_fp: '${toFp}',
        resistance: 0.3,
        capacitance: 0.5,
        strength: 0.0,
        conductance: 0.0,
        phase: 'standing',
        revision: 0,
        last_traversal_ts: ${ts}
      })`
    );

    await this._q(
      `MATCH (a:Aqueduct {fp: '${aqFp}'})
       MATCH (r:Room {fp: '${fromFp}'})
       CREATE (a)-[:AQUEDUCT_FROM]->(r)`
    );

    await this._q(
      `MATCH (a:Aqueduct {fp: '${aqFp}'})
       MATCH (r:Room {fp: '${toFp}'})
       CREATE (a)-[:AQUEDUCT_TO]->(r)`
    );

    // Derive a deterministic ActionLog fp for this aqueduct-created event.
    // Reusing deriveTripleFp as a generic 4-tuple hasher: (aqFp, "aqueduct-created", palaceFp, "").
    const aqActionFp = await deriveTripleFp(aqFp, 'aqueduct-created', pFp, String(ts));

    await this._q(
      `CREATE (:ActionLog {
        fp: '${aqActionFp}',
        palace_fp: '${pFp}',
        action_kind: 'aqueduct-created',
        actor_fp: '${pFp}',
        target_fp: '${aqFp}',
        parent_hashes: [],
        timestamp: ${ts},
        cbor_bytes_blake3: ''
      })`
    );

    return aqFp;
  }

  /**
   * Update an aqueduct's strength (Hebbian), conductance (Ebbinghaus), and
   * revision after a traversal. Resistance and capacitance are NEVER overwritten
   * by the runtime (AC10 invariant).
   */
  async updateAqueductStrength(
    aqueductFp: string,
    _actorFp: string,
    timestamp: number
  ): Promise<void> {
    this._gateWrite('updateAqueductStrength');
    const aqFp = sanitizeFp(aqueductFp, 'aqueductFp');
    const ts = sanitizeInt(timestamp, 'timestamp');
    const rows = await this._q<{
      strength: number;
      resistance: number;
      capacitance: number;
      revision: number;
      last_traversal_ts: number;
    }>(
      `MATCH (a:Aqueduct {fp: '${aqFp}'})
       RETURN a.strength AS strength, a.resistance AS resistance,
              a.capacitance AS capacitance, a.revision AS revision,
              a.last_traversal_ts AS last_traversal_ts`
    );

    if (rows.length === 0) {
      throw new Error(`updateAqueductStrength: Aqueduct '${aqFp}' not found`);
    }

    const { strength, resistance, revision, last_traversal_ts } = rows[0];
    const newStrength = updateStrength(Number(strength), DEFAULT_ALPHA);

    const lastTs = Number(last_traversal_ts ?? 0);
    const t_ms = lastTs > 0 ? ts - lastTs : 0;
    const newConductance = computeConductance(
      Number(resistance),
      newStrength,
      t_ms,
      DEFAULT_TAU_MS
    );
    const newRevision = Number(revision) + 1;

    await this._q(
      `MATCH (a:Aqueduct {fp: '${aqFp}'})
       SET a.strength = ${sanitizeFloat(newStrength, 'strength')},
           a.conductance = ${sanitizeFloat(newConductance, 'conductance')},
           a.revision = ${sanitizeInt(newRevision, 'revision')},
           a.last_traversal_ts = ${ts}`
    );
  }

  // ── Traversal round-trip (S5.5 — FR18 renderer half, D-007 CRITICAL) ────────

  /**
   * Record a room→room traversal in a single logical transaction.
   *
   * See StoreAPI.recordTraversal for full contract. Flow:
   *   1. Check aqueduct existence before create (distinguishes `aqueductCreated`
   *      flag in the returned tuple).
   *   2. Call getOrCreateAqueduct — if missing, materialises Aqueduct row with
   *      D-003 defaults (resistance=0.3, capacitance=0.5, strength=0, kind=visit)
   *      AND an aqueduct-created ActionLog entry (both derived fps).
   *   3. Call updateAqueductStrength — Hebbian saturating bump, TC17 monotone.
   *   4. Call recordAction for a `move` ActionLog entry. ActionLog fp derived
   *      from (fromFp, toFp, timestamp, palaceFp) via deriveTripleFp so
   *      replayable. cbor_bytes_blake3 pointer carries the derived fp as a
   *      sentinel until the Zig-side WASM signer parameterisation lands
   *      (known-gaps §6 — TODO-CRYPTO dual-sig Ed25519 + ML-DSA-87).
   *   5. Read-back the post-update aqueduct row so the renderer receives the
   *      post-commit strength/conductance/revision values — SEC11 ordering.
   */
  async recordTraversal(
    params: import('./store-types.js').RecordTraversalParams
  ): Promise<import('./store-types.js').RecordTraversalResult> {
    this._gateWrite('recordTraversal');
    const palaceFp = sanitizeFp(params.palaceFp, 'palaceFp');
    const fromFp = sanitizeFp(params.fromFp, 'fromFp');
    const toFp = sanitizeFp(params.toFp, 'toFp');
    const actorFp = sanitizeFp(params.actorFp ?? palaceFp, 'actorFp');
    const timestamp = sanitizeInt(params.timestamp ?? Date.now(), 'timestamp');

    // 1. Pre-check aqueduct existence by the palace-scoped derived fp. This is
    //    narrower than matching on (fromFp, toFp) alone — two palaces legitimately
    //    sharing rooms produce distinct aqueduct fps (M4 review fix). Race note:
    //    two concurrent recordTraversals for the same triple both observe
    //    existing=false and both report aqueductCreated=true; the second merge
    //    in getOrCreateAqueduct no-ops on the existing row, so the final DB state
    //    is correct. A real transactional fix awaits LadybugDB BEGIN/COMMIT
    //    (M5 — known-gaps).
    const derivedAqFp = await deriveAqueductFp(fromFp, toFp, palaceFp);
    const existing = await this._q<{ fp: string }>(
      `MATCH (a:Aqueduct {fp: '${derivedAqFp}'}) RETURN a.fp AS fp`
    );
    const aqueductCreated = existing.length === 0;

    // 2. Lazy create (paired aqueduct-created ActionLog emitted inside).
    const aqueductFp = await this.getOrCreateAqueduct(fromFp, toFp, palaceFp);

    // 3. Hebbian saturating bump.
    await this.updateAqueductStrength(aqueductFp, actorFp, timestamp);

    // 4. Emit signed `move` ActionLog entry. Derived fp ensures replay-identity
    //    AND is palace-scoped so two palaces sharing rooms cannot collide on the
    //    same (fromFp, toFp, timestamp) triple (M6 review fix).
    //    TODO-CRYPTO (known-gaps §6): the full Ed25519 + ML-DSA-87 dual sig is
    //    authored by the Zig signer — this MVP path persists the derived fp as
    //    the cbor_bytes_blake3 pointer so the row is well-formed and the Blake3
    //    handle is stable for the renderer (SEC11 "paint after persist").
    const moveActionFp = await deriveTripleFp(fromFp, toFp, `move:${palaceFp}`, String(timestamp));
    await this.recordAction({
      fp: moveActionFp,
      palaceFp,
      actionKind: 'move',
      actorFp,
      targetFp: aqueductFp,
      parentHashes: [],
      timestamp,
      cborBytesBlake3: moveActionFp,
    });

    // 5. Read-back post-update aqueduct values for the renderer tuple.
    const rows = await this._q<{
      strength: number;
      conductance: number;
      revision: number;
    }>(
      `MATCH (a:Aqueduct {fp: '${aqueductFp}'})
       RETURN a.strength AS strength, a.conductance AS conductance, a.revision AS revision`
    );
    if (rows.length === 0) {
      throw new Error(`recordTraversal: Aqueduct '${aqueductFp}' vanished post-write`);
    }

    return {
      moveActionFp,
      aqueductCreated,
      aqueductFp,
      newStrength: Number(rows[0].strength),
      newConductance: Number(rows[0].conductance),
      newRevision: Number(rows[0].revision),
      timestamp,
    };
  }

  // ── Oracle KG triple verbs (native graph storage) ───────────────────────────

  /**
   * Insert a triple as a native Triple node + HAS_KNOWLEDGE edge (S4.3 refresh).
   *
   * Replaces the prior JSON read-modify-write dance with an idempotent MERGE keyed
   * on the deterministic Triple.fp = blake3(agent||s||p||o). Subject and object
   * are validated as fps; predicate may be free text (e.g. "lives-in").
   */
  async insertTriple(agentFp: string, subject: string, predicate: string, object: string): Promise<void> {
    this._gateWrite('insertTriple');
    const a = sanitizeFp(agentFp, 'agentFp');
    const s = sanitizeFp(subject, 'subject');
    const o = sanitizeFp(object, 'object');
    const tripleFp = await deriveTripleFp(a, s, predicate, o);
    // Idempotent: existence check keyed on fp.
    const exists = await this._q<{ fp: string }>(
      `MATCH (t:Triple {fp: '${tripleFp}'}) RETURN t.fp AS fp`
    );
    if (exists.length > 0) return;
    const now = Date.now();
    await this._q(
      `CREATE (:Triple {
        fp: '${tripleFp}',
        agent_fp: '${a}',
        subject: '${s}',
        predicate: ${cypherString(predicate)},
        object: '${o}',
        created_at: ${now}
      })`
    );
    await this._q(
      `MATCH (a:Agent {fp: '${a}'})
       MATCH (t:Triple {fp: '${tripleFp}'})
       CREATE (a)-[:HAS_KNOWLEDGE]->(t)`
    );
  }

  /**
   * Delete a triple node keyed on its derived fp.
   */
  async deleteTriple(agentFp: string, subject: string, predicate: string, object: string): Promise<void> {
    this._gateWrite('deleteTriple');
    const a = sanitizeFp(agentFp, 'agentFp');
    const s = sanitizeFp(subject, 'subject');
    const o = sanitizeFp(object, 'object');
    const tripleFp = await deriveTripleFp(a, s, predicate, o);
    await this._q(`MATCH (t:Triple {fp: '${tripleFp}'}) DETACH DELETE t`);
  }

  /**
   * Replace (agent, subject, predicate, oldObject) with (agent, subject, predicate, newObject).
   */
  async updateTriple(
    agentFp: string,
    subject: string,
    predicate: string,
    oldObject: string,
    newObject: string
  ): Promise<void> {
    // Fps validated inside deleteTriple/insertTriple.
    await this.deleteTriple(agentFp, subject, predicate, oldObject);
    await this.insertTriple(agentFp, subject, predicate, newObject);
  }

  /**
   * Return triples for an agent. Pass fp='*' for all; otherwise filter by subject.
   */
  async triplesFor(agentFp: string, fp: string): Promise<Array<{ subject: string; predicate: string; object: string }>> {
    const a = sanitizeFp(agentFp, 'agentFp');
    if (fp === '*') {
      const rows = await this._q<{ subject: string; predicate: string; object: string }>(
        `MATCH (ag:Agent {fp: '${a}'})-[:HAS_KNOWLEDGE]->(t:Triple)
         RETURN t.subject AS subject, t.predicate AS predicate, t.object AS object`
      );
      return rows.map((r) => ({
        subject: String(r.subject),
        predicate: String(r.predicate),
        object: String(r.object),
      }));
    }
    const s = sanitizeFp(fp, 'subjectFp');
    const rows = await this._q<{ subject: string; predicate: string; object: string }>(
      `MATCH (ag:Agent {fp: '${a}'})-[:HAS_KNOWLEDGE]->(t:Triple {subject: '${s}'})
       RETURN t.subject AS subject, t.predicate AS predicate, t.object AS object`
    );
    return rows.map((r) => ({
      subject: String(r.subject),
      predicate: String(r.predicate),
      object: String(r.object),
    }));
  }

  /**
   * Return ActionLog rows for a palace added after a given timestamp (exclusive).
   *
   * Sprint-1 code review LOW-4: the previous implementation filtered on
   * `fp > cursor` — but content-addressed hex fps are NOT monotonically
   * ordered, so lex comparison returns a random subset. Replaced with
   * timestamp-based cursor: callers pass `{ afterTimestamp: number }` (ms
   * epoch) and the filter uses `timestamp > afterTimestamp`.
   *
   * Pass afterTimestamp=0 or omit to get all actions.
   */
  async actionsSince(palaceFp: string, opts?: { afterTimestamp?: number }): Promise<Array<{ fp: string; actionKind: string; targetFp: string; timestamp: number }>> {
    const pFp = sanitizeFp(palaceFp, 'palaceFp');
    const afterTs = opts?.afterTimestamp ?? 0;
    const tsInt = sanitizeInt(afterTs, 'afterTimestamp');
    const rows = await this._q<{ fp: string; action_kind: string; target_fp: string; timestamp: number | bigint }>(
      `MATCH (a:ActionLog {palace_fp: '${pFp}'})
       WHERE a.timestamp > ${tsInt}
       RETURN a.fp AS fp, a.action_kind AS action_kind, a.target_fp AS target_fp, a.timestamp AS timestamp
       ORDER BY a.timestamp`
    );
    return rows.map((r) => ({
      fp: String(r.fp),
      actionKind: String(r.action_kind),
      targetFp: String(r.target_fp),
      timestamp: typeof r.timestamp === 'bigint' ? Number(r.timestamp) : r.timestamp,
    }));
  }

  // ── S4.4 file-watcher domain verbs ──────────────────────────────────────────

  async updateInscription(avatarFp: string, fields: { source_blake3?: string; revision?: number }): Promise<void> {
    this._gateWrite('updateInscription');
    const iFp = sanitizeFp(avatarFp, 'avatarFp');
    const setClauses: string[] = [];
    if (fields.source_blake3 !== undefined) {
      const sb = sanitizeFp(fields.source_blake3, 'source_blake3');
      setClauses.push(`i.source_blake3 = '${sb}'`);
    }
    if (fields.revision !== undefined) {
      const rev = sanitizeInt(fields.revision, 'revision');
      setClauses.push(`i.revision = ${rev}`);
    }
    if (setClauses.length === 0) return;
    await this._q(
      `MATCH (i:Inscription {fp: '${iFp}'})
       SET ${setClauses.join(', ')}`
    );
  }

  async markOrphaned(avatarFp: string): Promise<void> {
    this._gateWrite('markOrphaned');
    const iFp = sanitizeFp(avatarFp, 'avatarFp');
    await this._q(
      `MATCH (i:Inscription {fp: '${iFp}'})
       SET i.orphaned = true`
    );
  }

  // ── Oracle fp registry (S4.2) ────────────────────────────────────────────────

  registerOracleFp(palaceFp: string, oracleFp: string): void {
    const p = sanitizeFp(palaceFp, 'palaceFp');
    const o = sanitizeFp(oracleFp, 'oracleFp');
    this._oracleFpByPalace.set(p, o);
    this._knownOracleFps.add(o);
  }

  /**
   * Set the active write context; returns a restore() closure.
   */
  setWriteContext(ctx: WriteContext): () => void {
    const prior = this._writeCtx;
    this._writeCtx = { requesterFp: ctx.requesterFp, origin: ctx.origin };
    return () => {
      this._writeCtx = prior;
    };
  }

  // ── Policy-gated read verbs (S4.2) ───────────────────────────────────────────

  async getInscription(avatarFp: string, requesterFp: string): Promise<InscriptionData | null> {
    const iFp = sanitizeFp(avatarFp, 'avatarFp');
    const rFp = sanitizeFp(requesterFp, 'requesterFp');
    const rows = await this._q<{
      fp: string;
      source_blake3: string;
      orphaned: boolean;
      created_at: number;
      policy: string;
      revision: number;
    }>(
      `MATCH (i:Inscription {fp: '${iFp}'})
       RETURN i.fp AS fp, i.source_blake3 AS source_blake3,
              i.orphaned AS orphaned, i.created_at AS created_at,
              i.policy AS policy, i.revision AS revision`
    );
    if (rows.length === 0) return null;

    const row = rows[0];
    const policy = sanitizePolicy(row.policy ?? 'public');

    // Resolve the palace fp for this inscription via LIVES_IN → Room → Palace
    const palaceRows = await this._q<{ palaceFp: string; guild_fps: unknown }>(
      `MATCH (i:Inscription {fp: '${iFp}'})-[:LIVES_IN]->(r:Room)<-[:CONTAINS]-(p:Palace)
       RETURN p.fp AS palaceFp, p.guild_fps AS guild_fps`
    );
    const palaceFp = palaceRows.length > 0 ? String(palaceRows[0].palaceFp) : '';
    const oracleFp = this._oracleFpByPalace.get(palaceFp) ?? '';

    // Read guild fps from Palace.guild_fps (STRING[] column, may be null/absent).
    let guildFps: string[] = [];
    if (palaceRows.length > 0) {
      const gfpRaw = palaceRows[0].guild_fps;
      if (Array.isArray(gfpRaw)) {
        guildFps = gfpRaw.map((v) => String(v)).filter((s) => s.length === 64);
      }
    }

    const slot: PolicySlot = {
      fp: iFp,
      palaceFp,
      policy,
      guildFps,
    };

    const decision = evaluateGuildPolicy(slot, rFp, palaceFp, {
      oracleFp,
      auditLog: defaultAuditLog,
    });

    if (!decision.allow) {
      throw new PolicyDeniedError(decision.reason, iFp);
    }

    return {
      fp: String(row.fp),
      source_blake3: String(row.source_blake3),
      orphaned: Boolean(row.orphaned),
      created_at: Number(row.created_at),
      policy,
      revision: Number(row.revision ?? 0),
    };
  }

  async mythosChainTriples(palaceFp: string, requesterFp: string): Promise<MythosTriple[]> {
    const pFp = sanitizeFp(palaceFp, 'palaceFp');
    const rFp = sanitizeFp(requesterFp, 'requesterFp');
    evaluateMythosPolicy(pFp, rFp, { auditLog: defaultAuditLog });

    const rows = await this._q<{ subject: string; predicate: string; object: string }>(
      `MATCH (p:Palace {fp: '${pFp}'})-[:MYTHOS_HEAD]->(m:Mythos)
       RETURN p.fp AS subject, 'mythos-head' AS predicate, m.fp AS object
       UNION ALL
       MATCH (p:Palace {fp: '${pFp}'})-[:MYTHOS_HEAD]->(head:Mythos)
       MATCH (head)-[:PREDECESSOR*0..]->(m:Mythos)-[:PREDECESSOR]->(prev:Mythos)
       RETURN m.fp AS subject, 'predecessor' AS predicate, prev.fp AS object`
    );

    return rows.map((r) => ({
      subject: String(r.subject),
      predicate: String(r.predicate),
      object: String(r.object),
    }));
  }

  // ── Palace / Room read verbs (S5.2 — PalaceLens consumer) ───────────────────

  async getPalace(palaceFp: string): Promise<PalaceData | null> {
    const fp = sanitizeFp(palaceFp);
    const rows = await this._q<{ fp: string }>(
      `MATCH (p:Palace {fp: ${fp}}) RETURN p.fp AS fp`
    );
    if (rows.length === 0) return null;
    return { fp: rows[0].fp, name: undefined, omnisphericalGrid: null };
  }

  async roomsFor(palaceFp: string): Promise<RoomData[]> {
    const fp = sanitizeFp(palaceFp);
    const rows = await this._q<{ fp: string }>(
      `MATCH (p:Palace {fp: ${fp}})-[:CONTAINS]->(r:Room) RETURN r.fp AS fp ORDER BY r.fp ASC`
    );
    return rows.map((r) => ({ fp: String(r.fp), layout: null }));
  }

  async roomContents(roomFp: string): Promise<import('./store-types.js').RoomContentsItem[]> {
    const fp = sanitizeFp(roomFp);
    const rows = await this._q<{ fp: string; surface: string | null }>(
      `MATCH (r:Room {fp: ${fp}})-[:CONTAINS]->(i:Inscription)
       RETURN i.fp AS fp, i.surface AS surface
       ORDER BY i.fp ASC`
    );
    return rows.map((r) => ({
      fp: String(r.fp),
      surface: r.surface != null ? String(r.surface) : undefined,
      // placement is null for MVP — jelly.layout nested decode deferred to Zig parser.
      placement: null,
    }));
  }

  /**
   * Fetch and hash-verify CAS body bytes for an inscription (S5.4 / D-007 / TC13 / AC3).
   *
   * 1. Queries `source_blake3` for the inscription fp.
   * 2. Reads the file from `_casDir/<source_blake3>` (SEC6: local filesystem only).
   * 3. Hash-verifies: asserts Blake3(bytes) === source_blake3. Throws on mismatch.
   *
   * No raw filesystem path is exposed to the lens — all CAS path logic is here.
   */
  async inscriptionMeta(inscriptionFp: string): Promise<import('./store-types.js').InscriptionMeta | null> {
    const iFp = sanitizeFp(inscriptionFp, 'inscriptionFp');
    const rows = await this._q<{ surface: string | null }>(
      `MATCH (i:Inscription {fp: '${iFp}'}) RETURN i.surface AS surface`
    );
    if (rows.length === 0) return null;
    const surface = rows[0].surface != null ? String(rows[0].surface) : 'scroll';
    // Fallback chain is not yet persisted on the Inscription node (envelope-level
    // `fallback` attribute per ADR §4 lands with the next protocol rev). Until then
    // an empty array is semantically correct — absent ≡ empty per ADR §4.
    return { fp: iFp, surface, fallback: [] };
  }

  async inscriptionBody(inscriptionFp: string): Promise<Uint8Array> {
    const iFp = sanitizeFp(inscriptionFp, 'inscriptionFp');
    // 1. Resolve source_blake3 from DB.
    const rows = await this._q<{ source_blake3: string }>(
      `MATCH (i:Inscription {fp: '${iFp}'}) RETURN i.source_blake3 AS source_blake3`
    );
    if (rows.length === 0) {
      throw new Error(`inscriptionBody: inscription '${iFp}' not found`);
    }
    const hash = sanitizeFp(String(rows[0].source_blake3), 'source_blake3');

    if (this._casDir === ':none:') {
      throw new Error(
        `inscriptionBody: CAS directory not configured (set opts.casDir or PALACE_CAS_DIR env var)`
      );
    }

    // 2. Read from CAS directory (SEC6: local FS only — no HTTP fetch).
    const { readFileSync } = await import('node:fs');
    const { join } = await import('node:path');
    const casPath = join(this._casDir, hash);
    let bytes: Uint8Array;
    try {
      bytes = new Uint8Array(readFileSync(casPath));
    } catch (err) {
      throw new Error(`inscriptionBody: CAS file not found for hash '${hash}': ${err}`);
    }

    // 3. Hash-verify: Blake3(bytes) must match stored source_blake3.
    const computed = await hashBytesBlake3Hex(bytes);
    if (computed !== hash) {
      throw new Error(
        `inscriptionBody: hash mismatch for inscription '${iFp}': ` +
        `stored=${hash} computed=${computed}`
      );
    }

    return bytes;
  }

  // ── Escape hatch ─────────────────────────────────────────────────────────────

  async __rawQuery<T = Record<string, unknown>>(cypher: string): Promise<T[]> {
    return this._q<T>(cypher);
  }

  // ── NFR18 / AC10: action mirror ──────────────────────────────────────────────

  async mirrorAction(action: MirrorAction): Promise<void> {
    const conn = this._conn;
    const exec = (cypher: string) => runQuery<Record<string, unknown>>(conn, cypher);
    await mirrorAction(exec, action, this);
  }
}

// ── Singleton factory ─────────────────────────────────────────────────────────

let _default: ServerStore | null = null;

export function getStore(dbPath?: string): ServerStore {
  if (dbPath !== undefined) {
    return new ServerStore(dbPath);
  }
  if (!_default) {
    _default = new ServerStore();
  }
  return _default;
}
