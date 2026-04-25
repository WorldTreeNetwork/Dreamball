/**
 * store.browser.ts — Browser-side StoreAPI implementation using kuzu-wasm@0.11.3.
 *
 * Mirror of store.server.ts — same validator imports, same `_gateWrite`, same
 * write context, same policy+revision-preserving upsertEmbedding, deterministic
 * aqueduct fp, and native Triple storage. See store.server.ts for the rationale
 * comments; the two files deliberately stay line-matched for reviewability.
 *
 * TC12: This file is the ONLY place that imports kuzu-wasm.
 * TC13: No CBOR bytes stored. Every reference is a Blake3 hex string.
 * D-007: Domain verbs only in the public surface. __rawQuery is the sole escape hatch.
 * D-015 (S2.1 outcome): LOCAL path — kNN uses local QUERY_VECTOR_INDEX.
 *   HTTP fallback branch preserved as TODO-KNN-FALLBACK (disabled by default).
 * AC2: setWorkerPath('/kuzu_wasm_worker.js') called exactly once per page load
 *   via module-level guard.
 * AC9: Non-Chromium warning emitted at open() time but execution continues.
 * AC10: Double-open safety — returns existing handle (idempotent open).
 */

import kuzu from 'kuzu-wasm';
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
import schemaDDL from './schema.cypher?raw';
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

// ── Worker path guard (AC2) ───────────────────────────────────────────────────

let _workerPathSet = false;

function ensureWorkerPath(): void {
  if (!_workerPathSet) {
    kuzu.setWorkerPath('/kuzu_wasm_worker.js');
    _workerPathSet = true;
  }
}

// ── Internal query wrapper ────────────────────────────────────────────────────

async function runQuery<T = Record<string, unknown>>(
  conn: InstanceType<typeof kuzu.Connection>,
  cypher: string
): Promise<T[]> {
  const qr = await conn.query(cypher);
  try {
    return (await qr.getAllObjects()) as T[];
  } finally {
    await qr.close();
  }
}

// ── DDL ───────────────────────────────────────────────────────────────────────

async function runDDL(conn: InstanceType<typeof kuzu.Connection>): Promise<void> {
  const tables = await runQuery<{ name: string }>(conn, 'CALL SHOW_TABLES() RETURN *');
  const existing = new Set(tables.map((r) => String(r.name)));

  const statements = schemaDDL
    .split('\n')
    .filter((line) => !line.trimStart().startsWith('--'))
    .join('\n')
    .split(';')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

  for (const stmt of statements) {
    const nodeMatch = stmt.match(/CREATE\s+NODE\s+TABLE\s+(\w+)/i);
    const relMatch = stmt.match(/CREATE\s+REL\s+TABLE\s+(\w+)/i);
    const tableName = nodeMatch?.[1] ?? relMatch?.[1];
    if (tableName && existing.has(tableName)) continue;
    await runQuery(conn, stmt);
  }

  await ensureVectorIndex(conn);
}

async function ensureVectorIndex(conn: InstanceType<typeof kuzu.Connection>): Promise<void> {
  try {
    const indexes = await runQuery<{ index_name: string }>(conn, 'CALL SHOW_INDEXES() RETURN *');
    const hasIndex = indexes.some((r) => String(r.index_name) === 'inscription_emb');
    if (!hasIndex) {
      await runQuery(
        conn,
        `CALL CREATE_VECTOR_INDEX('Inscription', 'inscription_emb', 'embedding')`
      );
    }
  } catch (err) {
    console.warn('kuzu-wasm: CREATE_VECTOR_INDEX failed (may be server-only):', err);
  }
}

// ── Non-Chromium detection (AC9) ──────────────────────────────────────────────

function checkBrowserWarning(): void {
  if (typeof navigator === 'undefined') return;
  const ua = navigator.userAgent;
  const isChromium =
    ua.includes('Chrome') || ua.includes('Chromium') || ua.includes('HeadlessChrome');
  if (!isChromium) {
    console.warn(
      'kuzu-wasm@0.11.3 validated on Chromium only; expect failures'
    );
  }
}

// ── kNN routing flag (D-015) ─────────────────────────────────────────────────

const KNN_LOCAL = true;

// ── BrowserStore ──────────────────────────────────────────────────────────────

export class BrowserStore implements StoreAPI {
  private db: InstanceType<typeof kuzu.Database> | null = null;
  private conn: InstanceType<typeof kuzu.Connection> | null = null;

  /** Per-palace oracle fp registry (S4.2). */
  private _oracleFpByPalace: Map<string, string> = new Map();
  private _knownOracleFps: Set<string> = new Set();

  /** Active write-context for the next mutation verb. */
  private _writeCtx: WriteContext = { requesterFp: '', origin: 'custodian' };

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  async open(): Promise<void> {
    if (this.conn !== null) {
      return;
    }

    ensureWorkerPath();
    checkBrowserWarning();

    try {
      await kuzu.FS.mkdir('/data');
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      if (!msg.includes('already') && !msg.includes('exists') && !msg.includes('EEXIST')) {
        throw err;
      }
    }

    await kuzu.FS.mountIdbfs('/data');
    await kuzu.FS.syncfs(true);

    this.db = new kuzu.Database('/data/palace.kz');
    this.conn = new kuzu.Connection(this.db);

    await runDDL(this.conn);
  }

  async close(): Promise<void> {
    if (this.conn === null) return;

    await this.conn.close();
    await this.db!.close();

    this.conn = null;
    this.db = null;

    await kuzu.FS.syncfs(false);
    await kuzu.FS.unmount('/data');
  }

  async syncfs(direction: 'in' | 'out'): Promise<void> {
    await kuzu.FS.syncfs(direction === 'in');
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  private get _conn(): InstanceType<typeof kuzu.Connection> {
    if (!this.conn) throw new Error('Store not open — call open() first');
    return this.conn;
  }

  private async _q<T = Record<string, unknown>>(cypher: string): Promise<T[]> {
    return runQuery<T>(this._conn, cypher);
  }

  /**
   * SEC5 / S4.2 AC5 write-gate. See store.server.ts for rationale.
   */
  private _gateWrite(verb: string): void {
    const { requesterFp, origin } = this._writeCtx;
    if (!requesterFp) return;
    if (!this._knownOracleFps.has(requesterFp)) return;
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

  async headHashes(palaceFp: string): Promise<string[]> {
    const pFp = sanitizeFp(palaceFp, 'palaceFp');
    const rows = await this._q<{ fp: string; parent_hashes: unknown }>(
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

  // ── Vector verbs ─────────────────────────────────────────────────────────────

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
   * K-nearest-neighbour query over Inscription.embedding (browser side).
   *
   * D-015 outcome: parity PASS (set-equal top-10, max|Δ|=0.000048) → local path.
   * D-016 Cypher pattern: QUERY_VECTOR_INDEX → YIELD node AS i, distance →
   * MATCH (i:Inscription)-[:LIVES_IN]->(r:Room) → RETURN fp, roomFp, distance
   * ORDER BY distance ASC. (AC2, AC6)
   *
   * TODO-KNN-FALLBACK: if D-015 parity degrades in a future kuzu-wasm release,
   * flip KNN_LOCAL to false and implement HttpBackend routing with console.warn.
   */
  async kNN(
    vec: Float32Array,
    k: number,
    _filter?: { palaceFp?: string; roomFp?: string }
  ): Promise<Array<{ fp: string; roomFp: string; distance: number }>> {
    if (!KNN_LOCAL) {
      // TODO-KNN-FALLBACK: route through jelly-server /kNN + one-time console.warn
      console.warn(
        'kNN: D-015 parity degraded — routing through HttpBackend (NFR11 relaxation)'
      );
      throw new Error('KNN HTTP fallback not implemented — TODO-KNN-FALLBACK');
    }
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
    const newConductance = computeConductance(Number(resistance), newStrength, t_ms, DEFAULT_TAU_MS);
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
   * See StoreAPI.recordTraversal for the full contract. Identical to
   * store.server.ts implementation (both adapters share the Cypher shape).
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

    // Pre-check via the palace-scoped derived aqueduct fp so shared rooms across
    // palaces don't return each other's flag (M4 review fix). Known race: two
    // concurrent recordTraversals on the same triple both observe existing=false
    // and both report aqueductCreated=true; DB state converges because
    // getOrCreateAqueduct MERGEs on the same derived fp (M5 — awaits BEGIN/COMMIT).
    const derivedAqFp = await deriveAqueductFp(fromFp, toFp, palaceFp);
    const existing = await this._q<{ fp: string }>(
      `MATCH (a:Aqueduct {fp: '${derivedAqFp}'}) RETURN a.fp AS fp`
    );
    const aqueductCreated = existing.length === 0;

    const aqueductFp = await this.getOrCreateAqueduct(fromFp, toFp, palaceFp);
    await this.updateAqueductStrength(aqueductFp, actorFp, timestamp);

    // Derived fp for the move action — palace-scoped (M6 review fix) so palaces
    // that share rooms don't collide on the same (fromFp, toFp, timestamp) triple.
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

  async insertTriple(agentFp: string, subject: string, predicate: string, object: string): Promise<void> {
    this._gateWrite('insertTriple');
    const a = sanitizeFp(agentFp, 'agentFp');
    const s = sanitizeFp(subject, 'subject');
    const o = sanitizeFp(object, 'object');
    const tripleFp = await deriveTripleFp(a, s, predicate, o);
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

  async deleteTriple(agentFp: string, subject: string, predicate: string, object: string): Promise<void> {
    this._gateWrite('deleteTriple');
    const a = sanitizeFp(agentFp, 'agentFp');
    const s = sanitizeFp(subject, 'subject');
    const o = sanitizeFp(object, 'object');
    const tripleFp = await deriveTripleFp(a, s, predicate, o);
    await this._q(`MATCH (t:Triple {fp: '${tripleFp}'}) DETACH DELETE t`);
  }

  async updateTriple(
    agentFp: string,
    subject: string,
    predicate: string,
    oldObject: string,
    newObject: string
  ): Promise<void> {
    await this.deleteTriple(agentFp, subject, predicate, oldObject);
    await this.insertTriple(agentFp, subject, predicate, newObject);
  }

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

  // ── S4.4 file-watcher domain verbs ───────────────────────────────────────────

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

  // ── Oracle fp registry (S4.2) ─────────────────────────────────────────────────

  registerOracleFp(palaceFp: string, oracleFp: string): void {
    const p = sanitizeFp(palaceFp, 'palaceFp');
    const o = sanitizeFp(oracleFp, 'oracleFp');
    this._oracleFpByPalace.set(p, o);
    this._knownOracleFps.add(o);
  }

  setWriteContext(ctx: WriteContext): () => void {
    const prior = this._writeCtx;
    this._writeCtx = { requesterFp: ctx.requesterFp, origin: ctx.origin };
    return () => {
      this._writeCtx = prior;
    };
  }

  // ── Policy-gated read verbs (S4.2) ────────────────────────────────────────────

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

    const palaceRows = await this._q<{ palaceFp: string; guild_fps: unknown }>(
      `MATCH (i:Inscription {fp: '${iFp}'})-[:LIVES_IN]->(r:Room)<-[:CONTAINS]-(p:Palace)
       RETURN p.fp AS palaceFp, p.guild_fps AS guild_fps`
    );
    const palaceFp = palaceRows.length > 0 ? String(palaceRows[0].palaceFp) : '';
    const oracleFp = this._oracleFpByPalace.get(palaceFp) ?? '';

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
   * Browser implementation: fetches from same-origin `/cas/<source_blake3>` (SEC6).
   * No cross-origin fetch — the browser store only reads from the same-origin jelly-server.
   * Hash-verifies: asserts Blake3(bytes) === source_blake3. Throws on mismatch.
   */
  async inscriptionMeta(inscriptionFp: string): Promise<import('./store-types.js').InscriptionMeta | null> {
    const iFp = sanitizeFp(inscriptionFp, 'inscriptionFp');
    const rows = await this._q<{ surface: string | null }>(
      `MATCH (i:Inscription {fp: '${iFp}'}) RETURN i.surface AS surface`
    );
    if (rows.length === 0) return null;
    const surface = rows[0].surface != null ? String(rows[0].surface) : 'scroll';
    // Fallback chain not yet persisted on the Inscription node (see store.server.ts).
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

    // 2. Fetch from same-origin CAS endpoint (SEC6: no non-local URL).
    const resp = await fetch(`/cas/${hash}`);
    if (!resp.ok) {
      throw new Error(`inscriptionBody: CAS fetch failed for hash '${hash}': ${resp.status}`);
    }
    const bytes = new Uint8Array(await resp.arrayBuffer());

    // 3. Hash-verify.
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

  // ── NFR18 / action mirror ─────────────────────────────────────────────────────

  async mirrorAction(action: MirrorAction): Promise<void> {
    const conn = this._conn;
    const exec = (cypher: string) => runQuery<Record<string, unknown>>(conn, cypher);
    await mirrorAction(exec, action, this);
  }
}

// ── Singleton factory ─────────────────────────────────────────────────────────

let _default: BrowserStore | null = null;

export function getStore(): BrowserStore {
  if (!_default) {
    _default = new BrowserStore();
  }
  return _default;
}
