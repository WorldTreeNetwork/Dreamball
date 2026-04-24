/**
 * action-mirror.ts — Sync a decoded jelly.action envelope into LadybugDB rows.
 *
 * Responsibility (D-016 / S2.4):
 *   Given a decoded action envelope + palace context, write within one logical
 *   transaction:
 *     1. An ActionLog row (commit-log, TC13 — no CBOR bytes, only blake3 fp)
 *     2. The graph mutations implied by the action kind
 *
 * Design: mirrorAction receives an `exec` function injected by the store
 * adapter. Both ServerStore and BrowserStore supply their own exec bound to
 * their internal runQuery. This avoids any direct DB import here and keeps
 * the mirror logic adapter-agnostic.
 *
 * Supported action kinds (RC2 — all 9): see the switch() below.
 *
 * TC13: ActionLog.cbor_bytes_blake3 stores the blake3 hash of the raw envelope,
 *       never the bytes themselves.
 *
 * Cypher-interpolation hardening: every dynamic value routes through a
 * cypher-utils.ts validator. No local esc()/escArr() helpers remain.
 */

import {
  sanitizeFp,
  sanitizeOptionalFp,
  sanitizeFpArray,
  sanitizeActionKind,
  sanitizeCanonicality,
  sanitizeInt,
  cypherFpArray,
} from './cypher-utils.js';

// ── Action shape ──────────────────────────────────────────────────────────────

export interface MirrorAction {
  /** Blake3 fp of the signed action envelope (PK for ActionLog) */
  fp: string;
  /** Palace this action belongs to */
  palace_fp: string;
  /** One of the 9 known action kinds per RC2 */
  action_kind: string;
  /** Agent who authored the action (or roomFp for avatar-inscribed) */
  actor_fp: string;
  /** Target node fp (room, inscription, aqueduct, mythos, …) */
  target_fp: string;
  /** Parent action fps (DAG edges) */
  parent_hashes: string[];
  /** ms-epoch timestamp */
  timestamp: number;
  /** Blake3 of the raw CBOR envelope — TC13 pointer only */
  cbor_bytes_blake3?: string;
  /** Extra fields for action kinds that carry more than actor+target */
  extra?: {
    /** aqueduct-created: source room fp */
    fromFp?: string;
    /** aqueduct-created: destination room fp */
    toFp?: string;
    /** true-naming: predecessor mythos fp (the old head) */
    predecessorFp?: string;
    /** true-naming: canonicality of new mythos */
    canonicality?: string;
    /** inscription-updated: new source blake3 */
    sourceBlake3?: string;
  };
}

// ── Exec function type ────────────────────────────────────────────────────────

export type ExecFn = (cypher: string) => Promise<Array<Record<string, unknown>>>;

export interface StoreForMirror {
  getOrCreateAqueduct(fromRoomFp: string, toRoomFp: string, palaceFp: string): Promise<string>;
  updateAqueductStrength(aqueductFp: string, actorFp: string, timestamp: number): Promise<void>;
}

// ── mirrorAction ──────────────────────────────────────────────────────────────

export async function mirrorAction(
  exec: ExecFn,
  action: MirrorAction,
  store?: StoreForMirror
): Promise<void> {
  const fp = sanitizeFp(action.fp, 'action.fp');
  const palace_fp = sanitizeFp(action.palace_fp, 'palace_fp');
  const action_kind = sanitizeActionKind(action.action_kind);
  const actor_fp = sanitizeFp(action.actor_fp, 'actor_fp');
  const target_fp = sanitizeOptionalFp(action.target_fp ?? '', 'target_fp');
  const parent_hashes = sanitizeFpArray(action.parent_hashes, 'parent_hashes');
  const timestamp = sanitizeInt(action.timestamp, 'timestamp');
  const cbor_bytes_blake3 = sanitizeOptionalFp(action.cbor_bytes_blake3 ?? '', 'cbor_bytes_blake3');
  const extra = action.extra ?? {};

  // AC6: for non-palace-minted actions, verify the palace exists first.
  if (action_kind !== 'palace-minted') {
    const palaceCheck = await exec(
      `MATCH (p:Palace {fp: '${palace_fp}'}) RETURN p.fp AS fp`
    );
    if (palaceCheck.length === 0) {
      throw new Error(
        `mirrorAction: palace '${palace_fp}' not found — rolling back action '${fp}' (kind: ${action_kind})`
      );
    }
  }

  // 1. Write ActionLog row (TC13: cbor_bytes_blake3 is a hash pointer, not bytes)
  const alExists = await exec(
    `MATCH (a:ActionLog {fp: '${fp}'}) RETURN a.fp AS fp`
  );
  if (alExists.length === 0) {
    await exec(
      `CREATE (:ActionLog {
        fp: '${fp}',
        palace_fp: '${palace_fp}',
        action_kind: '${action_kind}',
        actor_fp: '${actor_fp}',
        target_fp: '${target_fp}',
        parent_hashes: ${cypherFpArray(parent_hashes)},
        timestamp: ${timestamp},
        cbor_bytes_blake3: '${cbor_bytes_blake3}'
      })`
    );
  }

  // 2. Domain graph mutations per action kind
  switch (action_kind) {
    case 'palace-minted': {
      const pExists = await exec(
        `MATCH (p:Palace {fp: '${palace_fp}'}) RETURN p.fp AS fp`
      );
      if (pExists.length === 0) {
        await exec(
          `CREATE (:Palace {
            fp: '${palace_fp}',
            created_at: ${timestamp},
            mythos_head_fp: ''
          })`
        );
      }
      break;
    }

    case 'room-added': {
      const roomFp = sanitizeFp(target_fp, 'target_fp(roomFp)');
      const rExists = await exec(
        `MATCH (r:Room {fp: '${roomFp}'}) RETURN r.fp AS fp`
      );
      if (rExists.length === 0) {
        await exec(
          `CREATE (:Room {
            fp: '${roomFp}',
            created_at: ${timestamp}
          })`
        );
      }
      const cExists = await exec(
        `MATCH (p:Palace {fp: '${palace_fp}'})-[e:CONTAINS]->(r:Room {fp: '${roomFp}'})
         RETURN e`
      );
      if (cExists.length === 0) {
        await exec(
          `MATCH (p:Palace {fp: '${palace_fp}'})
           MATCH (r:Room {fp: '${roomFp}'})
           CREATE (p)-[:CONTAINS]->(r)`
        );
      }
      break;
    }

    case 'avatar-inscribed': {
      // Convention: actor_fp = roomFp, target_fp = inscriptionFp
      const roomFp = sanitizeFp(actor_fp, 'actor_fp(roomFp)');
      const inscFp = sanitizeFp(target_fp, 'target_fp(inscriptionFp)');
      // source_blake3 is the cbor_bytes_blake3 when present, otherwise the
      // inscription fp itself as a placeholder. Both are validated fps.
      const sourceBlake3 = cbor_bytes_blake3 || inscFp;

      const iExists = await exec(
        `MATCH (i:Inscription {fp: '${inscFp}'}) RETURN i.fp AS fp`
      );
      if (iExists.length === 0) {
        await exec(
          `CREATE (:Inscription {
            fp: '${inscFp}',
            source_blake3: '${sourceBlake3}',
            orphaned: false,
            created_at: ${timestamp},
            policy: 'public',
            revision: 0
          })`
        );
      }
      const rcExists = await exec(
        `MATCH (r:Room {fp: '${roomFp}'})-[e:CONTAINS]->(i:Inscription {fp: '${inscFp}'})
         RETURN e`
      );
      if (rcExists.length === 0) {
        await exec(
          `MATCH (r:Room {fp: '${roomFp}'})
           MATCH (i:Inscription {fp: '${inscFp}'})
           CREATE (r)-[:CONTAINS]->(i)`
        );
      }
      const liExists = await exec(
        `MATCH (i:Inscription {fp: '${inscFp}'})-[e:LIVES_IN]->(r:Room {fp: '${roomFp}'})
         RETURN e`
      );
      if (liExists.length === 0) {
        await exec(
          `MATCH (i:Inscription {fp: '${inscFp}'})
           MATCH (r:Room {fp: '${roomFp}'})
           CREATE (i)-[:LIVES_IN]->(r)`
        );
      }
      break;
    }

    case 'aqueduct-created': {
      const aqFp = sanitizeFp(target_fp, 'target_fp(aqueductFp)');
      const fromFp = sanitizeOptionalFp(extra.fromFp ?? '', 'extra.fromFp');
      const toFp = sanitizeOptionalFp(extra.toFp ?? '', 'extra.toFp');

      const aqExists = await exec(
        `MATCH (a:Aqueduct {fp: '${aqFp}'}) RETURN a.fp AS fp`
      );
      if (aqExists.length === 0) {
        await exec(
          `CREATE (:Aqueduct {
            fp: '${aqFp}',
            from_fp: '${fromFp}',
            to_fp: '${toFp}',
            resistance: 0.3,
            capacitance: 0.5,
            strength: 0.0,
            conductance: 0.0,
            phase: 'standing',
            revision: 0
          })`
        );
      }
      if (fromFp) {
        const afExists = await exec(
          `MATCH (a:Aqueduct {fp: '${aqFp}'})-[e:AQUEDUCT_FROM]->(r:Room {fp: '${fromFp}'})
           RETURN e`
        );
        if (afExists.length === 0) {
          await exec(
            `MATCH (a:Aqueduct {fp: '${aqFp}'})
             MATCH (r:Room {fp: '${fromFp}'})
             CREATE (a)-[:AQUEDUCT_FROM]->(r)`
          );
        }
      }
      if (toFp) {
        const atExists = await exec(
          `MATCH (a:Aqueduct {fp: '${aqFp}'})-[e:AQUEDUCT_TO]->(r:Room {fp: '${toFp}'})
           RETURN e`
        );
        if (atExists.length === 0) {
          await exec(
            `MATCH (a:Aqueduct {fp: '${aqFp}'})
             MATCH (r:Room {fp: '${toFp}'})
             CREATE (a)-[:AQUEDUCT_TO]->(r)`
          );
        }
      }
      break;
    }

    case 'true-naming': {
      const newMythosFp = sanitizeFp(target_fp, 'target_fp(newMythosFp)');
      const predecessorFp = sanitizeOptionalFp(extra.predecessorFp ?? '', 'extra.predecessorFp');
      const canonicality = sanitizeCanonicality(extra.canonicality ?? 'successor');

      const mExists = await exec(
        `MATCH (m:Mythos {fp: '${newMythosFp}'}) RETURN m.fp AS fp`
      );
      if (mExists.length === 0) {
        await exec(
          `CREATE (:Mythos {
            fp: '${newMythosFp}',
            body: '',
            canonicality: '${canonicality}',
            discovered_in_action_fp: '${fp}',
            created_at: ${timestamp}
          })`
        );
      }
      const headCheck = await exec(
        `MATCH (p:Palace {fp: '${palace_fp}'})-[e:MYTHOS_HEAD]->(:Mythos)
         RETURN e`
      );
      if (headCheck.length > 0) {
        await exec(
          `MATCH (p:Palace {fp: '${palace_fp}'})-[e:MYTHOS_HEAD]->(:Mythos)
           DELETE e`
        );
      }
      await exec(
        `MATCH (p:Palace {fp: '${palace_fp}'})
         MATCH (m:Mythos {fp: '${newMythosFp}'})
         CREATE (p)-[:MYTHOS_HEAD]->(m)`
      );
      if (predecessorFp) {
        const predExists = await exec(
          `MATCH (n:Mythos {fp: '${newMythosFp}'})-[e:PREDECESSOR]->(p:Mythos {fp: '${predecessorFp}'})
           RETURN e`
        );
        if (predExists.length === 0) {
          await exec(
            `MATCH (n:Mythos {fp: '${newMythosFp}'})
             MATCH (p:Mythos {fp: '${predecessorFp}'})
             CREATE (n)-[:PREDECESSOR]->(p)`
          );
        }
      }
      await exec(
        `MATCH (p:Palace {fp: '${palace_fp}'})
         SET p.mythos_head_fp = '${newMythosFp}'`
      );
      break;
    }

    case 'move': {
      const fromFp = sanitizeOptionalFp(extra.fromFp ?? '', 'extra.fromFp');
      const toFp = sanitizeOptionalFp(extra.toFp ?? '', 'extra.toFp');

      if (store && fromFp && toFp) {
        const aqFp = await store.getOrCreateAqueduct(fromFp, toFp, palace_fp);
        await store.updateAqueductStrength(aqFp, actor_fp, timestamp);
      } else if (!store) {
        console.warn(
          `mirrorAction: 'move' action '${fp}' — no store supplied; aqueduct strength not updated. Pass store argument for Hebbian updates.`
        );
      }
      break;
    }

    case 'inscription-updated': {
      const inscFp = sanitizeFp(target_fp, 'target_fp(inscriptionFp)');
      // extra.sourceBlake3 when present, otherwise fall back to the (already-validated)
      // cbor_bytes_blake3. Both are fps.
      const newBlake3 = extra.sourceBlake3
        ? sanitizeFp(extra.sourceBlake3, 'extra.sourceBlake3')
        : cbor_bytes_blake3;
      if (newBlake3) {
        await exec(
          `MATCH (i:Inscription {fp: '${inscFp}'})
           SET i.source_blake3 = '${newBlake3}'`
        );
      }
      break;
    }

    case 'inscription-orphaned': {
      const inscFp = sanitizeFp(target_fp, 'target_fp(inscriptionFp)');
      await exec(
        `MATCH (i:Inscription {fp: '${inscFp}'})
         SET i.orphaned = true`
      );
      break;
    }

    case 'inscription-pending-embedding': {
      // No graph mutation — embedding arrives later via reembed().
      break;
    }

    default: {
      // Unknown action_kind from forward-compat replay: fail-closed to prevent
      // silent divergence. Any new kind must be added to KNOWN_ACTION_KINDS in
      // cypher-utils.ts and handled here before it can reach production.
      throw new Error(
        `mirrorAction: unknown action_kind '${action_kind}' for fp '${fp}' — failing closed`
      );
    }
  }
}
